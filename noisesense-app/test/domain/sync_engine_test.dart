import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/errors.dart';
import 'package:noise_sense/domain/models/exposure_settings.dart';
import 'package:noise_sense/domain/models/noise_reading.dart';
import 'package:noise_sense/domain/repositories/noise_repository.dart';
import 'package:noise_sense/domain/repositories/outbox_store.dart';
import 'package:noise_sense/domain/services/sync_engine.dart';

import '../support/memory_outbox_store.dart';

/// A remote whose response to each reading is scripted by timestamp.
class _ScriptedRemote implements NoiseRepository {
  final sent = <DateTime>[];
  final Map<DateTime, NoiseSenseException> failures = {};
  NoiseSenseException? failAll;
  Completer<void>? gate;
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<SubmitOutcome> submit(NoiseReading reading) async {
    inFlight++;
    maxInFlight = math.max(maxInFlight, inFlight);
    try {
      await gate?.future;
      sent.add(reading.timestamp);
      final error = failAll ?? failures[reading.timestamp];
      if (error != null) throw error;
      return SubmitOutcome.stored;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<List<NoiseReading>> history() async => const [];
  @override
  Future<ExposureSettings> settings() async =>
      const ExposureSettings(thresholdDbA: 70, isDefault: true);
  @override
  Future<ExposureSettings> updateThreshold(double v) async =>
      ExposureSettings(thresholdDbA: v, isDefault: false);
}

class _Scheduler {
  final delays = <Duration>[];
  void Function()? pending;
  int cancelled = 0;

  Timer call(Duration delay, void Function() callback) {
    delays.add(delay);
    pending = callback;
    return _FakeTimer(this);
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._owner);
  final _Scheduler _owner;
  bool _active = true;
  @override
  void cancel() {
    if (_active) _owner.cancelled++;
    _active = false;
  }

  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

NoiseReading _r(int minute) =>
    NoiseReading(timestamp: DateTime.utc(2026, 10, 16, 9, minute), dbA: 60);

void main() {
  late MemoryOutboxStore store;
  late _ScriptedRemote remote;
  late _Scheduler scheduler;
  late SyncEngine engine;

  SyncEngine build({math.Random? random}) => SyncEngine(
    store: store,
    remote: remote,
    scheduler: scheduler.call,
    random: random,
  );

  setUp(() {
    store = MemoryOutboxStore();
    remote = _ScriptedRemote();
    scheduler = _Scheduler();
    engine = build();
  });

  tearDown(() => engine.dispose());

  test('readings are uploaded oldest first and then removed', () async {
    for (final m in [3, 1, 2]) {
      await store.add(_r(m));
    }
    await engine.flush();
    expect(remote.sent, [_r(1).timestamp, _r(2).timestamp, _r(3).timestamp]);
    expect(await store.all(), isEmpty);
  });

  test('enqueue stores the reading before any network attempt', () async {
    // Durability must not depend on the network.
    remote.gate = Completer<void>();
    await engine.enqueue(_r(1));
    expect(await store.all(), hasLength(1));
    expect(remote.sent, isEmpty, reason: 'upload still blocked');
    remote.gate!.complete();
    await settle();
  });

  group('when the service cannot be reached', () {
    test(
      'the pass stops at the first failure instead of trying every entry',
      () async {
        // Ten readings against a dead network should cost one request, not ten.
        for (var m = 0; m < 10; m++) {
          await store.add(_r(m));
        }
        remote.failAll = const ServiceUnavailableException('offline');
        await engine.flush();
        expect(remote.sent, hasLength(1));
        expect((await store.pending()).length, 10);
      },
    );

    test(
      'the failure is recorded on the entry and a retry is scheduled',
      () async {
        await store.add(_r(1));
        remote.failAll = const ServiceUnavailableException('timed out');
        await engine.flush();
        final e = store.entryAt(_r(1).timestamp)!;
        expect(e.attempts, 1);
        expect(e.lastError, 'timed out');
        expect(scheduler.delays, hasLength(1));
        expect(engine.status.retryAt, isNotNull);
      },
    );

    test('the retry succeeds once the network is back', () async {
      await store.add(_r(1));
      remote.failAll = const ServiceUnavailableException('offline');
      await engine.flush();
      remote.failAll = null;
      scheduler.pending!();
      await settle();
      expect(await store.all(), isEmpty);
      expect(engine.status.retryAt, isNull);
    });
  });

  group('backoff', () {
    test('the ceiling doubles per attempt and stops at the cap', () {
      // A random source that always returns its maximum shows the ceiling.
      final e = build(random: _MaxRandom());
      final seconds = [
        for (var a = 1; a <= 9; a++) e.backoffDelay(a).inMilliseconds / 1000,
      ];
      expect(seconds, [5, 10, 20, 40, 80, 160, 300, 300, 300]);
    });

    test('jitter spreads delays across the whole range', () {
      // Full jitter: uniform between the floor and the ceiling.
      final e = build(random: math.Random(42));
      final delays = [for (var i = 0; i < 2000; i++) e.backoffDelay(4)];
      final ms = delays.map((d) => d.inMilliseconds).toList()..sort();
      expect(ms.first, greaterThanOrEqualTo(1000), reason: 'floor');
      expect(ms.last, lessThanOrEqualTo(40000), reason: 'ceiling');
      final median = ms[ms.length ~/ 2];
      expect(median, inInclusiveRange(15000, 25000));
    });

    test('a very large attempt count does not overflow', () {
      final e = build(random: _MaxRandom());
      expect(e.backoffDelay(10000), const Duration(minutes: 5));
    });

    test('a success resets the backoff', () async {
      final e = build(random: _MaxRandom());
      await store.add(_r(1));
      remote.failAll = const ServiceUnavailableException('x');
      await e.flush();
      await e.flush();
      remote.failAll = null;
      await e.flush();
      await store.add(_r(2));
      remote.failAll = const ServiceUnavailableException('x');
      await e.flush();
      expect(scheduler.delays.last, const Duration(seconds: 5));
      await e.dispose();
    });
  });

  group('when the service refuses a reading', () {
    test('it is set aside and the readings behind it still go', () async {
      // One malformed reading must not block the queue for ever.
      for (var m = 1; m <= 3; m++) {
        await store.add(_r(m));
      }
      remote.failures[_r(2).timestamp] = const InvalidRequestException(
        'dbA out of range',
      );
      await engine.flush();
      expect(remote.sent, hasLength(3));
      final left = await store.all();
      expect(left, hasLength(1));
      expect(left.single.state, OutboxState.rejected);
      expect(left.single.lastError, 'dbA out of range');
      expect(engine.status.rejectedCount, 1);
      expect(scheduler.delays, isEmpty, reason: 'nothing to retry');
    });

    test('a rejected reading is never sent again', () async {
      await store.add(_r(1));
      remote.failAll = const InvalidRequestException('bad');
      await engine.flush();
      await engine.flush();
      expect(remote.sent, hasLength(1));
    });
  });

  group('when the session has ended', () {
    test('sync pauses and nothing is discarded', () async {
      await store.add(_r(1));
      await store.add(_r(2));
      remote.failAll = const UnauthorisedException('expired');
      await engine.flush();
      expect(engine.status.needsSignIn, isTrue);
      expect((await store.pending()).length, 2);
      expect(scheduler.delays, isEmpty, reason: 'retrying cannot help');
    });

    test('it stays paused until resumed, then sends everything', () async {
      await store.add(_r(1));
      remote.failAll = const UnauthorisedException('expired');
      await engine.flush();
      remote.failAll = null;
      await engine.flush();
      expect(remote.sent, hasLength(1), reason: 'paused');
      await engine.resume();
      expect(await store.all(), isEmpty);
      expect(engine.status.needsSignIn, isFalse);
    });
  });

  test(
    'overlapping flushes never upload the same entry concurrently',
    () async {
      // Measurement, the retry timer and app resume can all ask for a flush at once.
      for (var m = 0; m < 5; m++) {
        await store.add(_r(m));
      }
      remote.gate = Completer<void>();
      final a = engine.flush();
      final b = engine.flush();
      final c = engine.flush();
      remote.gate!.complete();
      await Future.wait([a, b, c]);
      expect(remote.maxInFlight, 1);
      expect(remote.sent, hasLength(5));
    },
  );

  test('a reading enqueued during a pass is picked up by that pass', () async {
    await store.add(_r(1));
    remote.gate = Completer<void>();
    final running = engine.flush();
    await engine.enqueue(_r(2));
    remote.gate!.complete();
    await running;
    await settle();
    expect(await store.all(), isEmpty);
  });

  test('start sends readings left over from a previous session', () async {
    await store.add(_r(1));
    await engine.start();
    expect(await store.all(), isEmpty);
  });

  test('status reports the pending timestamps', () async {
    remote.failAll = const ServiceUnavailableException('offline');
    await engine.enqueue(_r(1));
    await settle();
    expect(engine.status.pendingTimestamps, {_r(1).timestamp});
  });

  test('dispose cancels the retry and closes the store', () async {
    await store.add(_r(1));
    remote.failAll = const ServiceUnavailableException('offline');
    await engine.flush();
    await engine.dispose();
    expect(scheduler.cancelled, 1);
    expect(store.closed, isTrue);
  });
}

class _MaxRandom implements math.Random {
  @override
  double nextDouble() => 1.0;
  @override
  bool nextBool() => true;
  @override
  int nextInt(int max) => max - 1;
}
