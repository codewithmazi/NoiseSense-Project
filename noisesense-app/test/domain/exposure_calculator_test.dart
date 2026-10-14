import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/models/noise_reading.dart';
import 'package:noise_sense/domain/services/exposure_calculator.dart';

double log10(num x) => math.log(x) / math.ln10;

/// Treats timestamps as already in local time, so results are identical
/// whether the tests run in UTC (CI) or British Summer Time.
int _hourAsIs(DateTime t) => t.hour;

NoiseReading _at(int hour, double dbA, {double? laeq}) => NoiseReading(
  timestamp: DateTime.utc(2026, 10, 1, hour),
  dbA: dbA,
  laeq: laeq,
);

void main() {
  const calc = ExposureCalculator(localHour: _hourAsIs);
  const oneHour = Duration(hours: 1);

  group('energyAverage (golden values)', () {
    test('equal levels average to the same level', () {
      expect(ExposureCalculator.energyAverage([60, 60]), closeTo(60, 1e-9));
    });

    test('60 and 70 dB average to 67.40 dB, not the arithmetic 65 dB', () {
      expect(ExposureCalculator.energyAverage([60, 70]), closeTo(67.40, 0.01));
    });

    test('a loud period dominates: 80 and 50 dB average to 76.99 dB', () {
      expect(ExposureCalculator.energyAverage([80, 50]), closeTo(76.99, 0.01));
    });

    test('rejects an empty input rather than inventing a level', () {
      expect(() => ExposureCalculator.energyAverage([]), throwsArgumentError);
    });
  });

  group('ExposurePeriod boundaries', () {
    // Off-by-one errors at period edges are the classic bug here.
    const expected = {
      0: ExposurePeriod.night,
      6: ExposurePeriod.night,
      7: ExposurePeriod.day,
      18: ExposurePeriod.day,
      19: ExposurePeriod.evening,
      22: ExposurePeriod.evening,
      23: ExposurePeriod.night,
    };
    expected.forEach((hour, period) {
      test('$hour:00 is $period', () {
        expect(ExposurePeriod.forLocalHour(hour), period);
      });
    });

    test('rejects hours outside 0 to 23', () {
      expect(() => ExposurePeriod.forLocalHour(24), throwsRangeError);
      expect(() => ExposurePeriod.forLocalHour(-1), throwsRangeError);
    });
  });

  group('ldenStyle', () {
    test('no readings gives no level', () {
      expect(calc.ldenStyle([], window: oneHour), isNull);
    });

    test('a complete, evenly sampled day reproduces formal Lden', () {
      // Constant 60 dB for all 24 hours.
      final day = [for (var h = 0; h < 24; h++) _at(h, 60)];
      final dose = calc.ldenStyle(day, window: oneHour)!;

      // Formal Lden (2002/49/EC, Annex I): 12 h day, 4 h evening +5, 8 h night +10.
      final formal =
          10 *
          log10(
            (12 * math.pow(10, 60 / 10) +
                    4 * math.pow(10, (60 + 5) / 10) +
                    8 * math.pow(10, (60 + 10) / 10)) /
                24,
          );

      expect(dose.levelDb, closeTo(formal, 1e-9));
      // Known result: a constant level gives Lden about 6.4 dB above it.
      expect(dose.levelDb, closeTo(66.40, 0.01));
      expect(dose.coveredDuration, const Duration(hours: 24));
      expect(dose.readingCount, 24);
    });

    test('night readings carry a 10 dB penalty', () {
      expect(
        calc.ldenStyle([_at(2, 50)], window: oneHour)!.levelDb,
        closeTo(60, 1e-9),
      );
    });

    test('evening readings carry a 5 dB penalty', () {
      expect(
        calc.ldenStyle([_at(20, 50)], window: oneHour)!.levelDb,
        closeTo(55, 1e-9),
      );
    });

    test('day readings carry no penalty', () {
      expect(
        calc.ldenStyle([_at(12, 50)], window: oneHour)!.levelDb,
        closeTo(50, 1e-9),
      );
    });

    test('prefers LAeq over the instantaneous dB(A) value', () {
      final dose = calc.ldenStyle([_at(12, 70, laeq: 55)], window: oneHour)!;
      expect(dose.levelDb, closeTo(55, 1e-9));
    });

    test('rejects a non-positive window', () {
      expect(
        () => calc.ldenStyle([_at(12, 50)], window: Duration.zero),
        throwsArgumentError,
      );
    });
  });
}
