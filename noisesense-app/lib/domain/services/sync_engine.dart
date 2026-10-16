import 'dart:async';
import 'dart:math' as math;

import '../errors.dart';
import '../models/noise_reading.dart';
import '../repositories/noise_repository.dart';
import '../repositories/outbox_store.dart';

/// What the sync engine is doing, for display.
class SyncStatus {
  const SyncStatus({
    this.pendingTimestamps = const {},
    this.rejectedCount = 0,
    this.isSyncing = false,
    this.retryAt,
    this.needsSignIn = false,
    this.lastSyncedAt,
  });

  /// Readings held on the device and not yet acknowledged.
  final Set<DateTime> pendingTimestamps;

  /// Readings the service refused as invalid. Kept, not retried.
  final int rejectedCount;

  final bool isSyncing;

  /// When the next automatic retry will run, if one is scheduled.
  final DateTime? retryAt;

  /// The service refused the session. Sync is paused, nothing is discarded,
  /// and it resumes when [SyncEngine.resume] is called after sign-in.
  final bool needsSignIn;

  final DateTime? lastSyncedAt;

  int get pendingCount => pendingTimestamps.length;
}

/// Uploads outbox entries and decides what each failure means.
///
/// ## Consistency model
///
/// The device is the system of record for a reading until the service has
/// acknowledged it. This is the availability-first side of the trade-off the
/// CAP theorem describes (Gilbert & Lynch, 2002): measuring never blocks on
/// the network, and the cost is that the server's history lags the device's
/// for as long as the device is offline. Brewer (2012) argues that such
/// partitions are normal operating conditions to be designed for, and on a
/// phone carried through the day they are.
///
/// ## Failure policy
///
/// The failure types are sealed, so each is handled deliberately:
///
/// * [ServiceUnavailableException]: network loss, timeout, throttling or a
///   5xx. The entry stays pending and the pass stops; continuing would only
///   fail again against the same outage. A retry is scheduled with
///   exponential backoff and full jitter, the variant Brooker (2015) found
///   spreads synchronised clients most evenly. Jitter matters here because
///   the Learner Lab caps Lambda at ten concurrent executions: many phones
///   reconnecting together after an outage would otherwise retry in step.
/// * [UnauthorisedException]: the session ended. Sync pauses with nothing
///   discarded, and [SyncStatus.needsSignIn] lets the app ask the user to sign
///   in. Discarding here would lose data over an expired token.
/// * Anything else: the service understood the request and refused it, or
///   replied with something unexpected. Retrying would be refused again, so
///   the entry is set aside as rejected and the pass continues. Without this,
///   one malformed reading at the head of the queue would block every reading
///   behind it for ever.
///
/// Readings are uploaded one at a time because the API accepts one per
/// request. A batch endpoint would cut a night's backlog of ~480 requests to
/// a handful, and is recorded as future work.
class SyncEngine {
  SyncEngine({
    required this._store,
    required this._remote,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 5),
    math.Random? random,
    DateTime Function()? clock,
    Timer Function(Duration delay, void Function() callback)? scheduler,
  }) : _random = random ?? math.Random(),
       _clock = clock ?? DateTime.now,
       _schedule = scheduler ?? Timer.new;

  final OutboxStore _store;
  final NoiseRepository _remote;
  final math.Random _random;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _schedule;

  final Duration baseDelay;
  final Duration maxDelay;

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus();
  Timer? _retryTimer;
  int _consecutiveFailures = 0;
  bool _flushing = false;
  bool _flushAgain = false;
  bool _paused = false;
  bool _disposed = false;

  Stream<SyncStatus> get statusChanges => _statusController.stream;
  SyncStatus get status => _status;

  /// Holds a reading on the device, then tries to upload it.
  ///
  /// Returns once the reading is stored locally, not once it is uploaded. The
  /// caller's guarantee is durability, and that does not depend on the
  /// network.
  Future<void> enqueue(NoiseReading reading) async {
    await _store.add(reading);
    await _refreshStatus();
    unawaited(flush());
  }

  /// Uploads pending entries until the queue is empty or a failure stops it.
  ///
  /// Safe to call at any time. A call made while a pass is running does not
  /// start a second, concurrent pass, which could upload the same entry twice
  /// at once; it asks the running pass to look again when it finishes.
  Future<void> flush() async {
    if (_disposed || _paused) return;
    if (_flushing) {
      _flushAgain = true;
      return;
    }
    _flushing = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _emit(_copy(isSyncing: true, clearRetry: true));

    try {
      do {
        _flushAgain = false;
        final stop = await _pass();
        if (stop) break;
      } while (_flushAgain && !_disposed);
    } finally {
      _flushing = false;
      if (!_disposed) await _refreshStatus(isSyncing: false);
    }
  }

  /// Resumes after a sign-in. Pending entries are still there.
  Future<void> resume() async {
    _paused = false;
    _consecutiveFailures = 0;
    _emit(_copy(needsSignIn: false));
    await flush();
  }

  /// Returns true if the pass ended on a failure that should stop flushing.
  Future<bool> _pass() async {
    while (!_disposed) {
      final batch = await _store.pending();
      if (batch.isEmpty) return false;

      for (final entry in batch) {
        if (_disposed) return true;
        final ts = entry.reading.timestamp;
        try {
          // Stored and duplicate are both success: either way the service
          // now holds the reading.
          await _remote.submit(entry.reading);
          await _store.remove(ts);
          _consecutiveFailures = 0;
          _status = _copy(lastSyncedAt: _clock());
        } on NoiseSenseException catch (error) {
          switch (error) {
            case ServiceUnavailableException():
              await _store.recordFailure(ts, error.message);
              _scheduleRetry();
              return true;
            case UnauthorisedException():
              _paused = true;
              _emit(_copy(needsSignIn: true));
              return true;
            case InvalidRequestException() ||
                UnexpectedResponseException() ||
                ConfirmationRequiredException() ||
                AccountExistsException():
              await _store.reject(ts, error.message);
          }
        }
        await _refreshStatus(isSyncing: true);
      }
    }
    return true;
  }

  void _scheduleRetry() {
    _consecutiveFailures++;
    final delay = backoffDelay(_consecutiveFailures);
    _retryTimer?.cancel();
    _retryTimer = _schedule(delay, () => unawaited(flush()));
    _status = _copy(retryAt: _clock().add(delay));
  }

  /// Delay before retry number [attempt] (1-based): full jitter, uniformly
  /// random between zero and min(cap, base * 2^(attempt-1)).
  ///
  /// A one-second floor stops an unlucky draw near zero turning into an
  /// immediate retry against the outage that has just failed.
  Duration backoffDelay(int attempt) {
    final exponent = math.min(attempt - 1, 20);
    final ceilingMs = math.min(
      maxDelay.inMilliseconds,
      baseDelay.inMilliseconds * math.pow(2, exponent),
    );
    final ms = (_random.nextDouble() * ceilingMs).round();
    return Duration(milliseconds: math.max(ms, 1000));
  }

  Future<void> _refreshStatus({bool? isSyncing}) async {
    if (_disposed) return;
    final entries = await _store.all();
    _emit(
      _copy(
        pendingTimestamps: {
          for (final e in entries)
            if (e.state == OutboxState.pending) e.reading.timestamp,
        },
        rejectedCount: entries
            .where((e) => e.state == OutboxState.rejected)
            .length,
        isSyncing: isSyncing,
      ),
    );
  }

  SyncStatus _copy({
    Set<DateTime>? pendingTimestamps,
    int? rejectedCount,
    bool? isSyncing,
    DateTime? retryAt,
    bool clearRetry = false,
    bool? needsSignIn,
    DateTime? lastSyncedAt,
  }) => SyncStatus(
    pendingTimestamps: pendingTimestamps ?? _status.pendingTimestamps,
    rejectedCount: rejectedCount ?? _status.rejectedCount,
    isSyncing: isSyncing ?? _status.isSyncing,
    retryAt: clearRetry ? null : (retryAt ?? _status.retryAt),
    needsSignIn: needsSignIn ?? _status.needsSignIn,
    lastSyncedAt: lastSyncedAt ?? _status.lastSyncedAt,
  );

  void _emit(SyncStatus s) {
    if (_disposed) return;
    _status = s;
    _statusController.add(s);
  }

  /// Readings held on the device, pending or rejected, so they can be shown
  /// alongside the service's history while it does not have them.
  Future<List<NoiseReading>> unsyncedReadings() async => [
    for (final e in await _store.all()) e.reading,
  ];

  /// Loads the outbox's current state, and uploads anything left over from a
  /// previous session.
  Future<void> start() async {
    await _refreshStatus();
    await flush();
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _statusController.close();
    await _store.close();
  }
}
