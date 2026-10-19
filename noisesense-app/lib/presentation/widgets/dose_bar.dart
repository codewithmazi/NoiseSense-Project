import 'package:flutter/material.dart';

import '../../domain/services/exposure_calculator.dart';
import '../exposure_tone.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';

/// Cumulative dose as a share of the user's limit, after the wireframe's
/// "64% of daily limit" bar.
///
/// The percentage is on an equal-energy basis
/// ([ExposureCalculator.doseFraction]). The bar fills to 100% and stops; the
/// figure beside it keeps counting, so 200% is still reported as 200%.
///
/// The covered time is always printed with it. Formal Lden assumes a full
/// 24-hour record and a phone rarely provides one, so a dose without its
/// coverage would overstate what has been measured.
class DoseBar extends StatelessWidget {
  const DoseBar({super.key, required this.dose, required this.limitDb});

  final ExposureDose? dose;
  final double? limitDb;

  @override
  Widget build(BuildContext context) {
    final d = dose;
    final limit = limitDb;
    if (d == null || limit == null) {
      return const Text(
        'No exposure recorded yet. Start measuring to build up your dose.',
        style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 14),
      );
    }

    final fraction = ExposureCalculator.doseFraction(d.levelDb, limit);
    final tone = ExposureTone.of(d.levelDb, limit);
    final percent = (fraction * 100).round();

    return Semantics(
      label:
          'Cumulative dose $percent percent of your ${limit.round()} decibel '
          'limit, ${tone.label.toLowerCase()}. ${_coverage(d)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: AppTheme.radius,
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 14,
              color: tone.colour,
              backgroundColor: AppTheme.surfaceContainer,
            ),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            '$percent% of your limit · limit ${Formatters.threshold(limit)}',
            style: TextStyle(
              color: tone == ExposureTone.normal
                  ? AppTheme.onSurface
                  : tone.colour,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${tone.label}. ${_coverage(d)}',
            style: const TextStyle(
              color: AppTheme.onSurfaceMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _coverage(ExposureDose d) =>
      'Lden-weighted ${Formatters.level(d.levelDb)} over '
      '${Formatters.duration(d.coveredDuration)} of measurement.';
}
