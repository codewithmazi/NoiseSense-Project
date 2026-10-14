import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/errors.dart';
import 'package:noise_sense/domain/models/exposure_settings.dart';
import 'package:noise_sense/domain/models/noise_reading.dart';
import 'package:noise_sense/domain/repositories/noise_repository.dart';
import 'package:noise_sense/domain/services/exposure_calculator.dart';
import 'package:noise_sense/presentation/view_models/dashboard_view_model.dart';

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

/// A reading at a fixed local hour, so period penalties are deterministic.
NoiseReading _reading(double dbA, {int hour = 12}) =>
    NoiseReading(timestamp: DateTime.utc(2026, 10, 11, hour), dbA: dbA);

void main() {
  late _FakeNoiseRepository repository;
  late int expiryCalls;
  late DashboardViewModel viewModel;

  DashboardViewModel build({Duration window = const Duration(minutes: 1)}) =>
      DashboardViewModel(
        repository: repository,
        onSessionExpired: () async => expiryCalls++,
        // The local hour is pinned, so the day/evening/night penalty applied
        // does not depend on the machine's time zone. Without this the same
        // test would produce different figures in CI (UTC) and on a developer
        // machine in British Summer Time.
        calculator: ExposureCalculator(localHour: (utc) => utc.hour),
        measurementWindow: window,
      );

  setUp(() {
    repository = _FakeNoiseRepository();
    expiryCalls = 0;
    viewModel = build();
  });

  group('loading', () {
    test(
      'readings and settings are fetched together, not one after the other',
      () async {
        // Proves concurrency rather than just that both were called: history is
        // held open, and settings must already have been requested while it is
        // still in flight. Serialising the two would roughly double the wait on
        // a connection where a round trip can include a Lambda cold start.
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
        // The distinction the UI depends on: "not loaded yet" must not render
        // as "you have no history".
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
      // 60 dB and 70 dB average to 67.4 dB, not 65 dB. Getting this wrong
      // would understate exposure, which for a health tool is the dangerous
      // direction to be wrong in.
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
      // Same sound level, different hour: the Lden weighting must change the
      // result, or the whole cumulative-dose model is cosmetic.
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
    test('a stored reading appears immediately without a re-read', () async {
      await viewModel.load();
      final sent = await viewModel.submitReading(_reading(80));
      expect(sent, isTrue);
      expect(viewModel.readings, hasLength(1));
      // No second history call: DynamoDB reads are eventually consistent, so
      // re-reading could legitimately omit the write that just succeeded.
      expect(repository.calls.where((c) => c == 'history').length, 1);
    });

    test('the newest reading is placed first', () async {
      repository.readings = [_reading(60)];
      await viewModel.load();
      await viewModel.submitReading(_reading(90));
      expect(viewModel.readings.first.dbA, 90);
    });

    test(
      'a duplicate counts as success, because the data is already safe',
      () async {
        // The offline replay path depends on this. Treating a duplicate as a
        // failure would make correct behaviour look broken (FR-06).
        await viewModel.load();
        repository.submitOutcome = SubmitOutcome.duplicate;
        final sent = await viewModel.submitReading(_reading(80));
        expect(sent, isTrue);
        expect(viewModel.errorMessage, isNull);
      },
    );

    test('a duplicate is not added to the list a second time', () async {
      repository.readings = [_reading(60)];
      await viewModel.load();
      repository.submitOutcome = SubmitOutcome.duplicate;
      await viewModel.submitReading(_reading(60));
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

  group('session expiry', () {
    test(
      'a rejected token ends the session instead of showing an error',
      () async {
        repository.historyError = const UnauthorisedException('Not signed in');
        await viewModel.load();
        expect(expiryCalls, 1);
        // No message: the user is about to see the sign-in screen, which
        // explains itself.
        expect(viewModel.errorMessage, isNull);
      },
    );

    test('a rejected token on submit also ends the session', () async {
      await viewModel.load();
      repository.submitError = const UnauthorisedException('Not signed in');
      final sent = await viewModel.submitReading(_reading(80));
      expect(sent, isFalse);
      expect(expiryCalls, 1);
    });

    test('an ordinary failure does not end the session', () async {
      // The negative case. If every error signed the user out, a single
      // dropped connection would log them out mid-walk.
      repository.historyError = const ServiceUnavailableException('offline');
      await viewModel.load();
      expect(expiryCalls, 0);
    });
  });
}
