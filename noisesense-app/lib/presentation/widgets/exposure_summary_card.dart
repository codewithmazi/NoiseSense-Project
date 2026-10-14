import 'package:flutter/material.dart';

import '../../domain/services/exposure_calculator.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';

/// The headline figure: cumulative exposure, with the context needed to read
/// it honestly.
///
/// This card is where the 602 design was deliberately replaced. That version
/// alerted on any single reading above a fixed 70 dB(A), which treats a
/// one-second door slam and a night of traffic as the same risk. What is shown
/// here is an Lden-style dose: an energy average with the evening and night
/// penalties from the EU Environmental Noise Directive (2002/49/EC, Annex I)
/// applied, so the figure reflects accumulated exposure rather than a peak.
///
/// Three things are shown together, never the level alone:
///
/// * the dose, as the large figure;
/// * the measured time it covers, because a dose over twenty minutes is not
///   comparable with one over a day and the level alone hides that;
/// * how it compares with the threshold the user chose.
///
/// Showing the coverage is the point of intellectual honesty in this screen.
/// Formal Lden assumes a complete 24-hour record, and a phone almost never
/// provides one, so presenting the number without its coverage would overstate
/// what has actually been measured.
class ExposureSummaryCard extends StatelessWidget {
  const ExposureSummaryCard({
    super.key,
    required this.dose,
    required this.thresholdDbA,
  });

  /// The computed dose, or null when there are no readings yet.
  final ExposureDose? dose;

  /// The user's alert level, or null before settings have loaded.
  final double? thresholdDbA;

  @override
  Widget build(BuildContext context) {
    final current = dose;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: current == null ? _empty() : _summary(current),
      ),
    );
  }

  Widget _empty() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'No exposure recorded yet',
        style: TextStyle(
          color: AppTheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      SizedBox(height: AppTheme.spaceSm),
      Text(
        'Once readings are taken, your cumulative exposure will appear here.',
        style: TextStyle(
          color: AppTheme.onSurfaceMuted,
          fontSize: 15,
          height: 1.4,
        ),
      ),
    ],
  );

  Widget _summary(ExposureDose current) {
    final threshold = thresholdDbA;
    final isOver = threshold != null && current.levelDb >= threshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cumulative exposure',
          style: TextStyle(
            color: AppTheme.onSurfaceMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        // The figure and its unit are one semantic string, so a screen reader
        // reads "67.4 decibels A-weighted" rather than announcing a bare
        // number followed by a separate fragment.
        Semantics(
          label:
              'Cumulative exposure ${Formatters.levelValue(current.levelDb)} '
              'decibels A-weighted',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Formatters.levelValue(current.levelDb),
                style: const TextStyle(
                  color: AppTheme.onSurface,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: AppTheme.spaceXs),
              const Text(
                'dB(A)',
                style: TextStyle(
                  color: AppTheme.onSurfaceMuted,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Text(
          'Lden-weighted, over ${Formatters.duration(current.coveredDuration)} '
          'of measurement (${current.readingCount} '
          '${current.readingCount == 1 ? 'reading' : 'readings'}).',
          style: const TextStyle(
            color: AppTheme.onSurfaceMuted,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        if (threshold != null) ...[
          const SizedBox(height: AppTheme.spaceMd),
          const Divider(),
          const SizedBox(height: AppTheme.spaceMd),
          Row(
            children: [
              // Icon as well as colour, so the comparison does not depend on
              // distinguishing red from blue (WCAG 2.2 SC 1.4.1).
              Icon(
                isOver
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                size: 20,
                color: isOver ? AppTheme.error : AppTheme.primary,
                semanticLabel: '',
              ),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Text(
                  isOver
                      ? 'Above your ${Formatters.threshold(threshold)} alert level.'
                      : 'Below your ${Formatters.threshold(threshold)} alert level.',
                  style: TextStyle(
                    color: isOver ? AppTheme.error : AppTheme.onSurface,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
