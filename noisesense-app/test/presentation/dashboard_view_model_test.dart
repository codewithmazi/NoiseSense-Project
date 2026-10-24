import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/errors.dart';
import 'package:noise_sense/domain/models/exposure_settings.dart';
import 'package:noise_sense/domain/models/noise_reading.dart';
import 'package:noise_sense/domain/repositories/noise_repository.dart';
import 'package:noise_sense/domain/services/exposure_calculator.dart';
import 'package:noise_sense/domain/services/sync_engine.dart';
import 'package:noise_sense/presentation/view_models/dashboard_view_model.dart';

import '../support/memory_outbox_store.dart';

class _FakeNoiseRepository implements NoiseRepository {
  List<NoiseReading> readings = const [];
  ExposureSettings stored = const ExposureSettings(
    thresholdDbA: 70,
    isDefault: true,
  );
  SubmitOutcome submitOutcome = SubmitOutcome.stored;

  NoiseSenseException? historyError;
  NoiseSenseException? settingsError;
  NoiseSenseException? submitError;
  NoiseSenseException? updateError;

  final List<String> calls = [];
  double? lastThresholdSent;
  NoiseReading? lastReadingSent;

  /// Set to delay history, so a test can observe the loading state.
  Completer<void>? historyGate;

  @override
  Future<List<NoiseReading>> history() async {
    calls.add('history');
    await historyGate?.future;
    final error = historyError;
    if (error != null) throw error;
    return readings;
  }

  @override
  Future<ExposureSettings> settings() async {
    calls.add('settings');
    final error = settingsError;
    if (error != null) throw error;
    return stored;
  }

  @override
  Future<SubmitOutcome> submit(NoiseReading reading) async {
    calls.add('submit');
    lastReadingSent = reading;
    final error = submitError;
    if (error != null) throw error;
    return submitOutcome;
  }

  @override
  Future<ExposureSettings> updateThreshold(double thresholdDbA) async {
    calls.add('updateThreshold');
    lastThresholdSent = thresholdDbA;
    final error = updateError;
    if (error != null) throw error;
    stored = ExposureSettings(
      thresholdDbA: thresholdDbA,
      isDefault: false,
      updatedAt: DateTime.utc(2026, 10, 11, 12),
    );
    return stored;
  }
}

int _nextMinute = 0;

/// A reading at a fixed local hour, so period penalties are deterministic.
NoiseReading _reading(double dbA, {int hour = 12, int? minute}) => NoiseReading(
  timestamp: DateTime.utc(2026, 10, 11, hour, minute ?? (_nextMinute++ % 60)),
  dbA: dbA,
);

/// A scheduler that records retries instead of running them, so tests decide when a retry happens.
class _ManualScheduler {
  final delays = <Duration>[];
  void Function()? pending;

  Timer call(Duration delay, void Function() callback) {
    delays.add(delay);
    pending = callback;
    return Timer(const Duration(days: 365), () {});
  }
}

void main() {
  late _FakeNoiseRepository repository;
  late MemoryOutboxStore outbox;
  late _ManualScheduler scheduler;
  late int expiryCalls;
  late DashboardViewModel viewModel;

  DashboardViewModel build({Duration window = const Duration(minutes: 1)}) =>
      DashboardViewModel(
        repository: repository,
        sync: SyncEngine(
          store: outbox,
          remote: repository,
          scheduler: scheduler.call,
        ),
        onSessionExpired: () async => expiryCalls++,
        // The local hour is pinned, so the day/evening/night penalty applied does not depend on the machine's time zone.
        calculator: ExposureCalculator(localHour: (utc) => utc.hour),
        measurementWindow: window,
      );

  setUp(() {
    repository = _FakeNoiseRepository();
    outbox = MemoryOutboxStore();
    scheduler = _ManualScheduler();
    expiryCalls = 0;
    viewModel = build();
  });

  group('loading', () {
    test(
      'readings and settings are fetched together, not one after the other',
      () async {
        // Proves concurrency rather than just that both were called.
        repository.historyGate = Completer<void>();
        final pending = viewModel.load();

        // Let the microtask queue run, without releasing the gate.
        await Future<void>.delayed(Duration.zero);
        expect(
          repository.calls,
          contains('settings'),
          reason: 'settings should not be waiting for history to return',
        );

        repository.historyGate!.complete();
        await pending;
      },
    );

    test(
      'an empty list before the first load is not reported as no readings',
      () {
        // The distinction the UI depends on: "not loaded yet" must not render as "you have no history".
        expect(viewModel.hasLoadedOnce, isFalse);
        expect(viewModel.readings, isEmpty);
      },
    );

    test('hasLoadedOnce is set even when the load fails', () async {
      repository.historyError = const ServiceUnavailableException('offline');
      await viewModel.load();
      expect(viewModel.hasLoadedOnce, isTrue);
      expect(viewModel.isLoading, isFalse);
    });

    test(
      'a concurrent load is ignored rather than doubling the requests',
      () async {
        repository.historyGate = Completer<void>();
        final first = viewModel.load();
        final second = viewModel.load();
        repository.historyGate!.complete();
        await Future.wait([first, second]);
        expect(repository.calls.where((c) => c == 'history').length, 1);
      },
    );

    test('a failure shows a message and leaves the screen usable', () async {
      repository.historyError = const ServiceUnavailableException('timed out');
      await viewModel.load();
      expect(viewModel.errorMessage, contains('connection'));
      expect(viewModel.isLoading, isFalse);
    });
  });

  group('dose', () {
    test('is null with no readings, because no level is defined', () async {
      await viewModel.load();
      expect(viewModel.dose, isNull);
    });

    test('is the energy average, not the arithmetic mean', () async {
      // 60 dB and 70 dB average to 67.4 dB, not 65 dB.
      repository.readings = [_reading(60), _reading(70)];
      await viewModel.load();
      expect(viewModel.dose!.levelDb, closeTo(67.4, 0.05));
    });

    test('reports the time it covers, not just the level', () async {
      repository.readings = [_reading(60), _reading(70), _reading(65)];
      viewModel = build(window: const Duration(minutes: 5));
      await viewModel.load();
      expect(viewModel.dose!.coveredDuration, const Duration(minutes: 15));
      expect(viewModel.dose!.readingCount, 3);
    });

    test('night readings carry the +10 dB penalty', () async {
      // Same sound level, different hour.
      repository.readings = [_reading(60, hour: 12)];
      await viewModel.load();
      final day = viewModel.dose!.levelDb;

      repository.readings = [_reading(60, hour: 2)];
      viewModel = build();
      await viewModel.load();
      final night = viewModel.dose!.levelDb;

      expect(night - day, closeTo(10.0, 0.001));
    });
  });

  group('threshold comparison', () {
    test('is false before settings have arrived', () {
      expect(viewModel.isOverThreshold, isFalse);
    });

    test('is true when the dose reaches the chosen level', () async {
      repository.stored = const ExposureSettings(
        thresholdDbA: 65,
        isDefault: false,
      );
      repository.readings = [_reading(70)];
      await viewModel.load();
      expect(viewModel.isOverThreshold, isTrue);
    });

    test('is false when the dose is below it', () async {
      repository.stored = const ExposureSettings(
        thresholdDbA: 85,
        isDefault: false,
      );
      repository.readings = [_reading(70)];
      await viewModel.load();
      expect(viewModel.isOverThreshold, isFalse);
    });
  });

  group('saving the threshold', () {
    test(
      'adopts the value the service confirms, not the one requested',
      () async {
        await viewModel.load();
        final saved = await viewModel.updateThreshold(75);
        expect(saved, isTrue);
        expect(viewModel.settings!.thresholdDbA, 75);
        // And it is no longer flagged as the service default.
        expect(viewModel.settings!.isDefault, isFalse);
      },
    );

    test('a rejected value leaves the previous setting in place', () async {
      await viewModel.load();
      repository.updateError = const InvalidRequestException('out of range');
      final saved = await viewModel.updateThreshold(120);
      expect(saved, isFalse);
      expect(viewModel.settings!.thresholdDbA, 70);
      expect(viewModel.errorMessage, 'out of range');
    });

    test('saving does not blank the readings already on screen', () async {
      repository.readings = [_reading(70)];
      await viewModel.load();
      await viewModel.updateThreshold(75);
      // isSaving is separate from isLoading precisely so this holds.
      expect(viewModel.readings, hasLength(1));
      expect(viewModel.dose, isNotNull);
    });
  });

  group('submitting a reading', () {
    test('a reading appears immediately, without a re-read', () async {
      await viewModel.load();
      final saved = await viewModel.submitReading(_reading(80));
      expect(saved, isTrue);
      expect(viewModel.readings, hasLength(1));
      await settle();
      // No second history call: DynamoDB reads are eventually consistent.
      expect(repository.calls.where((c) => c == 'history').length, 1);
    });

    test('it is uploaded, then no longer marked as waiting', () async {
      await viewModel.load();
      final r = _reading(80);
      await viewModel.submitReading(r);
      await settle();
      expect(repository.lastReadingSent, r);
      expect(viewModel.isPending(r), isFalse);
      expect(outbox.entryAt(r.timestamp), isNull);
    });

    test('the newest reading is placed first', () async {
      repository.readings = [_reading(60, minute: 0)];
      await viewModel.load();
      await viewModel.submitReading(_reading(90, minute: 5));
      expect(viewModel.readings.first.dbA, 90);
    });

    test('a duplicate counts as success, because the data is safe', () async {
      // The offline replay path depends on this (FR-06).
      await viewModel.load();
      repository.submitOutcome = SubmitOutcome.duplicate;
      final r = _reading(80);
      expect(await viewModel.submitReading(r), isTrue);
      await settle();
      expect(viewModel.errorMessage, isNull);
      expect(outbox.entryAt(r.timestamp), isNull);
    });

    test('a reading already in history is not listed twice', () async {
      final r = _reading(60);
      repository.readings = [r];
      await viewModel.load();
      await viewModel.submitReading(r);
      expect(viewModel.readings, hasLength(1));
    });

    test('the dose is recomputed when a reading is added', () async {
      repository.readings = [_reading(60)];
      await viewModel.load();
      final before = viewModel.dose!.levelDb;
      await viewModel.submitReading(_reading(90));
      expect(viewModel.dose!.levelDb, greaterThan(before));
    });
  });

  group('offline', () {
    test(
      'a reading measured offline is kept, shown, and marked waiting',
      () async {
        // The case the outbox exists for. Before it, this reading was lost.
        await viewModel.load();
        repository.submitError = const ServiceUnavailableException('no signal');
        final r = _reading(75);
        final saved = await viewModel.submitReading(r);
        await settle();

        expect(
          saved,
          isTrue,
          reason: 'saved on the phone, which is what counts',
        );
        expect(viewModel.readings, contains(r));
        expect(viewModel.isPending(r), isTrue);
        expect(viewModel.syncStatus.pendingCount, 1);
        expect(viewModel.syncStatus.retryAt, isNotNull);
        // No error banner: nothing is wrong that the user needs to act on.
        expect(viewModel.errorMessage, isNull);
      },
    );

    test('the waiting reading is sent once the network is back', () async {
      await viewModel.load();
      repository.submitError = const ServiceUnavailableException('no signal');
      final r = _reading(75);
      await viewModel.submitReading(r);
      await settle();

      repository.submitError = null;
      scheduler.pending!(); // the scheduled retry fires
      await settle();
      expect(viewModel.isPending(r), isFalse);
      expect(viewModel.syncStatus.pendingCount, 0);
    });

    test(
      'unsent readings from before are shown even if history fails',
      () async {
        // Opening the app underground must still show what was measured.
        final r = _reading(66);
        await outbox.add(r);
        repository.historyError = const ServiceUnavailableException('offline');
        await viewModel.load();
        expect(viewModel.readings, contains(r));
      },
    );

    test('a reading the phone cannot store is reported as lost', () async {
      outbox.addError = Exception('disk full');
      final saved = await viewModel.submitReading(_reading(70));
      expect(saved, isFalse);
      expect(viewModel.errorMessage, contains('storage'));
    });
  });

  group('session expiry', () {
    test(
      'a rejected token ends the session instead of showing an error',
      () async {
        repository.historyError = const UnauthorisedException('Not signed in');
        await viewModel.load();
        expect(expiryCalls, 1);
        // No message: the user is about to see the sign-in screen, which explains itself.
        expect(viewModel.errorMessage, isNull);
      },
    );

    test(
      'a rejected token during upload ends the session but keeps the reading',
      () async {
        await viewModel.load();
        repository.submitError = const UnauthorisedException('Not signed in');
        final r = _reading(80);
        final saved = await viewModel.submitReading(r);
        await settle();
        expect(saved, isTrue);
        expect(expiryCalls, 1);
        // Still on the phone, to be sent after the user signs back in.
        expect(outbox.entryAt(r.timestamp), isNotNull);
      },
    );

    test('an ordinary failure does not end the session', () async {
      // The negative case.
      repository.historyError = const ServiceUnavailableException('offline');
      await viewModel.load();
      expect(expiryCalls, 0);
    });
  });
}
