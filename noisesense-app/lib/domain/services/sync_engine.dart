import 'dart:async';
import 'dart:math' as math;

import '../errors.dart';
import '../models/noise_reading.dart';
import '../repositories/noise_repository.dart';
import '../repositories/outbox_store.dart';

/// Current sync state, for display.
class SyncStatus {
  const SyncStatus({
    this.pendingTimestamps = const {},
    this.rejectedCount = 0,
    this.isSyncing = false,
    this.retryAt,
    this.needsSignIn = false,
    this.lastSyncedAt,
  });

  /// Readings held locally and not yet acknowledged.
  final Set<DateTime> pendingTimestamps;

  /// Readings rejected by the service.
  final int rejectedCount;

  final bool isSyncing;

  /// Next scheduled automatic retry, if any.
  final DateTime? retryAt;

  /// True when sync is paused pending sign-in.
  final bool needsSignIn;

  final DateTime? lastSyncedAt;

  int get pendingCount => pendingTimestamps.length;
}

/// Uploads outbox entries and handles upload failures.
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

  /// Stores a reading locally, then attempts to upload it.
  Future<void> enqueue(NoiseReading reading) async {
    await _store.add(reading);
    await _refreshStatus();
    unawaited(flush());
  }

  /// Uploads pending entries until empty or a stopping failure occurs.
  /// Concurrent calls are coalesced into the running pass.
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

  /// Resumes sync after sign-in.
  Future<void> resume() async {
    _paused = false;
    _consecutiveFailures = 0;
    _emit(_copy(needsSignIn: false));
    await flush();
  }

  /// Returns true if the pass stopped on a retry-blocking failure.
  Future<bool> _pass() async {
    while (!_disposed) {
      final batch = await _store.pending();
      if (batch.isEmpty) return false;

      for (final entry in batch) {
        if (_disposed) return true;
        final ts = entry.reading.timestamp;
        try {
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

  /// Exponential backoff with full jitter and a one-second floor.
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

  /// All locally held readings, pending or rejected.
  Future<List<NoiseReading>> unsyncedReadings() async => [
    for (final e in await _store.all()) e.reading,
  ];

  /// Loads outbox state and uploads leftover entries.
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