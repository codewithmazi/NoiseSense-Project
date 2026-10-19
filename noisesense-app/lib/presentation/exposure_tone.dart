import 'dart:ui';

import '../domain/services/exposure_calculator.dart';
import 'theme/app_theme.dart';

/// The wireframes' three-colour scheme, given a precise rule.
///
/// The wireframes say "teal = normal, amber = approaching limit, coral =
/// exceedance" but not where "approaching" starts. Here it starts at half the
/// allowed energy, which is 3 dB below the limit (see
/// [ExposureCalculator.doseFraction]). The boundary therefore falls where the
/// physics puts it rather than at an arbitrary number of decibels.
enum ExposureTone {
  normal,
  approaching,
  over;

  static const double approachingFraction = 0.5;

  static ExposureTone of(double levelDb, double? limitDb) {
    if (limitDb == null) return normal;
    final f = ExposureCalculator.doseFraction(levelDb, limitDb);
    if (f >= 1) return over;
    if (f >= approachingFraction) return approaching;
    return normal;
  }

  Color get colour => switch (this) {
    normal => AppTheme.primary,
    approaching => AppTheme.warning,
    over => AppTheme.error,
  };

  /// Words for the tone. Shown beside the colour, never instead of it, so the
  /// state does not depend on telling teal from amber (WCAG 2.2 SC 1.4.1).
  String get label => switch (this) {
    normal => 'Within your limit',
    approaching => 'Approaching your limit',
    over => 'Above your limit',
  };
}
