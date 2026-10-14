import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/presentation/theme/app_theme.dart';
import 'package:noise_sense/presentation/theme/contrast.dart';

/// Measures the theme's colour contrast against WCAG 2.2.
///
/// The purpose is to turn an accessibility claim into a measurement. "The
/// palette is accessible" is an assertion a marker has to take on trust; a
/// failing test and a printed ratio of 3.9:1 is evidence. The ratios this
/// prints are the figures reported for experiment M9.
///
/// It also guards against the usual way a palette decays: a colour nudged for
/// appearance, months later, quietly dropping below the threshold. Here that
/// breaks the build.
void main() {
  group('Contrast arithmetic', () {
    test('black against white is the maximum ratio of 21:1', () {
      // The known anchor for the formula. If this is wrong, every other
      // number in the file is wrong too.
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
        // Compositing is the caller's job. Returning a number here would be
        // worse than failing, because it would look authoritative.
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

      // Printed whether or not the test passes, so the report can quote the
      // measured figures rather than just "it passed".
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
      // Records a defect this test suite found and the fix for it. The panel
      // fill sits around 1.2:1 against the page, which is invisible, and no
      // pair of dark backgrounds can reach 3:1 while still carrying readable
      // text. The boundary was therefore moved onto an explicit border.
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
      // The dose is set at 44pt, which WCAG would judge as large text at 3:1.
      // It is held to 4.5:1 anyway: it is the single most important number in
      // the app, and the stricter threshold costs nothing to meet here.
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
