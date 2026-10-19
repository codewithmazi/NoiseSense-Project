import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/services/exposure_calculator.dart';
import 'package:noise_sense/presentation/exposure_tone.dart';
import 'package:noise_sense/presentation/theme/app_theme.dart';

void main() {
  group('dose fraction (equal energy)', () {
    test('at the limit is 100%', () {
      expect(ExposureCalculator.doseFraction(70, 70), closeTo(1.0, 1e-12));
    });

    test('3 dB under is about half, 3 dB over about double', () {
      // 10^(0.3) = 1.995, the physical basis for the 3 dB exchange rate.
      expect(ExposureCalculator.doseFraction(67, 70), closeTo(0.501, 0.001));
      expect(ExposureCalculator.doseFraction(73, 70), closeTo(1.995, 0.001));
    });

    test('10 dB under is 10%, not 86% as a linear ratio would say', () {
      // The negative case: a naive 60/70 percentage badly overstates headroom
      // in the other direction too.
      expect(ExposureCalculator.doseFraction(60, 70), closeTo(0.1, 1e-12));
      expect(60 / 70, isNot(closeTo(0.1, 0.5 - 0.1)));
    });

    test('the device test day reads as about 163% of a 70 dB limit', () {
      // 72.1 dB(A), the dose measured on the S9+ on 16 Oct.
      expect(ExposureCalculator.doseFraction(72.1, 70), closeTo(1.622, 0.001));
    });
  });

  group('tone', () {
    test('boundaries sit at 50% and 100% of the allowed energy', () {
      expect(ExposureTone.of(66.9, 70), ExposureTone.normal);
      expect(ExposureTone.of(67.0, 70), ExposureTone.approaching);
      expect(ExposureTone.of(69.9, 70), ExposureTone.approaching);
      expect(ExposureTone.of(70.0, 70), ExposureTone.over);
    });

    test('with no limit loaded yet, nothing is flagged', () {
      expect(ExposureTone.of(95, null), ExposureTone.normal);
    });

    test('each tone has words as well as a colour (SC 1.4.1)', () {
      final labels = ExposureTone.values.map((t) => t.label).toSet();
      expect(labels, hasLength(3));
      expect(ExposureTone.values.map((t) => t.colour).toSet(), {
        AppTheme.primary,
        AppTheme.warning,
        AppTheme.error,
      });
    });
  });
}
