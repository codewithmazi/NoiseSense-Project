import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/models/exposure_settings.dart';
import 'package:noise_sense/domain/models/noise_reading.dart';

void main() {
  group('NoiseReading', () {
    test('normalises the timestamp to UTC whole seconds', () {
      final r = NoiseReading(
        timestamp: DateTime.utc(2026, 10, 9, 14, 30, 5, 999, 999),
        dbA: 60,
      );
      expect(r.timestamp, DateTime.utc(2026, 10, 9, 14, 30, 5));
      expect(r.timestamp.isUtc, isTrue);
    });

    test(
      'readings in the same second are equal, so a replay is a duplicate',
      () {
        final a = NoiseReading(
          timestamp: DateTime.utc(2026, 10, 9, 14, 30, 5, 100),
          dbA: 60,
        );
        final b = NoiseReading(
          timestamp: DateTime.utc(2026, 10, 9, 14, 30, 5, 900),
          dbA: 60,
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      },
    );

    test('rejects levels no real reading could have', () {
      expect(
        () => NoiseReading(timestamp: DateTime.utc(2026), dbA: double.nan),
        throwsArgumentError,
      );
      expect(
        () => NoiseReading(timestamp: DateTime.utc(2026), dbA: -1),
        throwsArgumentError,
      );
      expect(
        () => NoiseReading(
          timestamp: DateTime.utc(2026),
          dbA: 60,
          laeq: double.infinity,
        ),
        throwsArgumentError,
      );
    });

    test('rejects classifier confidence outside 0 to 1', () {
      expect(
        () => NoiseReading(
          timestamp: DateTime.utc(2026),
          dbA: 60,
          confidence: 1.2,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ExposureSettings.validateThreshold', () {
    test('accepts the inclusive range 40 to 100 dB(A)', () {
      expect(ExposureSettings.validateThreshold(40), isNull);
      expect(ExposureSettings.validateThreshold(70), isNull);
      expect(ExposureSettings.validateThreshold(100), isNull);
    });

    test(
      'rejects values just outside the range, with a message for the user',
      () {
        expect(ExposureSettings.validateThreshold(39.9), isNotNull);
        expect(ExposureSettings.validateThreshold(100.1), isNotNull);
        expect(ExposureSettings.validateThreshold(double.nan), isNotNull);
      },
    );
  });
}
