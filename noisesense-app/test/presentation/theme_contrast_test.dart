import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/presentation/theme/app_theme.dart';
import 'package:noise_sense/presentation/theme/contrast.dart';

/// Measures the theme's colour contrast against WCAG 2.2.
void main() {
  group('Contrast arithmetic', () {
    test('black against white is the maximum ratio of 21:1', () {
      // The known anchor for the formula.
      expect(
        Contrast.ratio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.01),
      );
    });

    test('a colour against itself is 1:1', () {
      expect(
        Contrast.ratio(const Color(0xFF4FA3E3), const Color(0xFF4FA3E3)),
        closeTo(1.0, 0.0001),
      );
    });

    test('order of arguments does not change the result', () {
      const a = Color(0xFF0F1B2D);
      const b = Color(0xFFE8EDF4);
      expect(Contrast.ratio(a, b), closeTo(Contrast.ratio(b, a), 0.0001));
    });

    test('white has a relative luminance of 1 and black of 0', () {
      expect(
        Contrast.relativeLuminance(const Color(0xFFFFFFFF)),
        closeTo(1.0, 0.0001),
      );
      expect(
        Contrast.relativeLuminance(const Color(0xFF000000)),
        closeTo(0.0, 0.0001),
      );
    });

    test(
      'a translucent colour is rejected rather than given a false ratio',
      () {
        // Compositing is the caller's job.
        expect(
          () =>
              Contrast.ratio(const Color(0x800F1B2D), const Color(0xFFFFFFFF)),
          throwsArgumentError,
        );
      },
    );
  });

  group('Theme meets WCAG 2.2 AA', () {
    test('every text pair reaches 4.5:1 (SC 1.4.3)', () {
      final measured = <String, double>{};
      final failures = <String>[];

      AppTheme.textPairs.forEach((name, pair) {
        final ratio = Contrast.ratio(pair.$1, pair.$2);
        measured[name] = ratio;
        if (ratio < Contrast.aaNormalText) {
          failures.add('$name: ${ratio.toStringAsFixed(2)}:1');
        }
      });

      // Printed whether or not the test passes.
      _report('WCAG 2.2 SC 1.4.3 text contrast (requires 4.5:1)', measured);

      expect(failures, isEmpty, reason: 'Below 4.5:1: ${failures.join('; ')}');
    });

    test('every non-text pair reaches 3:1 (SC 1.4.11)', () {
      final measured = <String, double>{};
      final failures = <String>[];

      AppTheme.nonTextPairs.forEach((name, pair) {
        final ratio = Contrast.ratio(pair.$1, pair.$2);
        measured[name] = ratio;
        if (ratio < Contrast.aaNonText) {
          failures.add('$name: ${ratio.toStringAsFixed(2)}:1');
        }
      });

      _report('WCAG 2.2 SC 1.4.11 non-text contrast (requires 3:1)', measured);

      expect(failures, isEmpty, reason: 'Below 3:1: ${failures.join('; ')}');
    });

    test('panels are bounded by an outline, not by their fill alone', () {
      // Records a defect this suite found, and its fix.
      final fill = Contrast.ratio(AppTheme.surfaceContainer, AppTheme.surface);
      final border = Contrast.ratio(AppTheme.outlineSubtle, AppTheme.surface);

      _report('Panel boundary', {
        'fill against page (informational)': fill,
        'border against page (SC 1.4.11)': border,
      });

      expect(
        fill,
        lessThan(Contrast.aaNonText),
        reason:
            'if the fill ever did reach 3:1 the border would be redundant '
            'and this reasoning should be revisited',
      );
      expect(border, greaterThanOrEqualTo(Contrast.aaNonText));
    });

    test('the large headline figure clears the stricter normal-text bar', () {
      // The 44pt dose figure is held to 4.5:1 anyway.
      expect(
        Contrast.ratio(AppTheme.onSurface, AppTheme.surfaceContainer),
        greaterThanOrEqualTo(Contrast.aaNormalText),
      );
    });

    test('touch targets are at least the 24px WCAG minimum (SC 2.5.8)', () {
      expect(AppTheme.minTouchTarget, greaterThanOrEqualTo(24));
      // And in fact meet the larger Material figure, which is the real target.
      expect(AppTheme.minTouchTarget, greaterThanOrEqualTo(48));
    });
  });
}

void _report(String heading, Map<String, double> measured) {
  final lines = measured.entries
      .map((e) => '  ${e.key.padRight(26)} ${e.value.toStringAsFixed(2)}:1')
      .join('\n');
  // ignore: avoid_print
  print('\n$heading\n$lines\n');
}
