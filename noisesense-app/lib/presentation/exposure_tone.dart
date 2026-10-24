import 'dart:ui';

import '../domain/services/exposure_calculator.dart';
import 'theme/app_theme.dart';

/// Maps exposure to the wireframes' three colours.
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

  /// Words for the tone.
  String get label => switch (this) {
    normal => 'Within your limit',
    approaching => 'Approaching your limit',
    over => 'Above your limit',
  };
}
