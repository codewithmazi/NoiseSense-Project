import 'package:flutter/material.dart';

import '../exposure_tone.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';
import '../view_models/dashboard_view_model.dart';
import '../widgets/screen_shell.dart';
import '../widgets/section_label.dart';

/// Tab 3, "Summary".
///
/// The wireframe shows a weekly summary produced by the Step Functions
/// workflow. The app cannot show that yet: the API has no route that returns
/// the stored weekly summaries, and the history route is capped at 100
/// readings, so a week cannot be rebuilt on the phone either. Until that route
/// exists, this screen summarises the readings the app does hold and says
/// plainly what they cover, rather than presenting a short sample as a week.
///
/// The wireframe's "Risk: Moderate" band is deliberately omitted. No
/// validated mapping from a phone's short personal sample to a health-risk
/// category was found, and inventing one would present a guess as a finding.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.dashboard});

  final DashboardViewModel dashboard;

  /// WHO Environmental Noise Guidelines for the European Region (2018):
  /// recommended level for road traffic noise, as Lden.
  static const double whoRoadTrafficLden = 53;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dashboard,
      builder: (context, _) {
        final readings = dashboard.readings;
        final dose = dashboard.dose;
        final limit = dashboard.settings?.thresholdDbA;

        return ScreenShell(
          title: 'Summary',
          children: [
            if (dose == null || readings.isEmpty)
              const Text(
                'No readings yet. A summary appears once you have measured.',
                style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 15),
              )
            else ...[
              SectionLabel(
                'Your last ${readings.length} readings · '
                '${Formatters.duration(dose.coveredDuration)} measured',
              ),
              Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: 'Average (Lden-weighted)',
                      value: Formatters.level(dose.levelDb),
                      tone: ExposureTone.of(dose.levelDb, limit),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: _Figure(
                      label: 'Loudest moment',
                      value: Formatters.level(_peak(dashboard)),
                      tone: ExposureTone.of(_peak(dashboard), limit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('WHO guideline'),
                      Text(
                        dose.levelDb > whoRoadTrafficLden
                            ? '${Formatters.levelValue(dose.levelDb - whoRoadTrafficLden)} dB '
                                  'above the WHO guideline of 53 dB Lden for road '
                                  'traffic noise.'
                            : 'At or below the WHO guideline of 53 dB Lden for '
                                  'road traffic noise.',
                        style: const TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spaceXs),
                      // The comparison is offered as a guide, with the reason
                      // it is only a guide, because the two figures are not
                      // measured the same way.
                      const Text(
                        'A guide, not a like-for-like comparison: the WHO '
                        'figure is a long-term average outside the home, and '
                        'this is a short personal sample from an uncalibrated '
                        'phone.',
                        style: TextStyle(
                          color: AppTheme.onSurfaceMuted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppTheme.spaceMd),
            const Text(
              'Weekly summaries are generated on the server each week and will '
              'appear here once the app can fetch them.',
              style: TextStyle(
                color: AppTheme.onSurfaceMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The loudest fast-weighted moment. Each reading's dbA carries its
  /// window's loudest 125 ms block.
  static double _peak(DashboardViewModel vm) =>
      vm.readings.map((r) => r.dbA).reduce((a, b) => a > b ? a : b);
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final ExposureTone tone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Semantics(
          label: '$label $value, ${tone.label.toLowerCase()}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.onSurfaceMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: AppTheme.spaceXs),
              Text(
                value,
                style: TextStyle(
                  color: tone == ExposureTone.normal
                      ? AppTheme.onSurface
                      : tone.colour,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
