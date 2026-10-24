import 'package:flutter/material.dart';

import '../../domain/acoustics/microphone_calibration.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';
import '../view_models/dashboard_view_model.dart';
import '../view_models/measurement_view_model.dart';
import '../widgets/dose_bar.dart';
import '../widgets/level_gauge.dart';
import '../widgets/message_banner.dart';
import '../widgets/reading_tile.dart';
import '../widgets/screen_shell.dart';
import '../widgets/section_label.dart';
import '../widgets/sync_status_view.dart';

/// Tab 1, "Monitor": the wireframes' Home — Live Monitor screen.
class MonitorScreen extends StatelessWidget {
  const MonitorScreen({
    super.key,
    required this.dashboard,
    required this.measurement,
  });

  final DashboardViewModel dashboard;
  final MeasurementViewModel measurement;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([dashboard, measurement]),
      builder: (context, _) {
        final m = measurement;
        final limit = dashboard.settings?.thresholdDbA;
        final latest = dashboard.readings.isEmpty
            ? null
            : dashboard.readings.first;

        final double? gaugeLevel;
        final String caption;
        if (m.isMeasuring) {
          gaugeLevel = m.liveLevelDb;
          caption = 'dB(A) · live, updated every second';
        } else if (latest != null) {
          gaugeLevel = latest.laeq ?? latest.dbA;
          caption =
              'dB(A) · LAeq of the minute from '
              '${Formatters.timestamp(latest.timestamp)}';
        } else {
          gaugeLevel = null;
          caption = 'Start measuring to see the level around you';
        }

        return ScreenShell(
          title: m.isMeasuring ? 'Monitoring' : 'Monitor',
          actions: [SyncChip(status: dashboard.syncStatus)],
          children: [
            if (dashboard.errorMessage != null) ...[
              MessageBanner(message: dashboard.errorMessage),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            LevelGauge(levelDb: gaugeLevel, limitDb: limit, caption: caption),
            _SourceChip(
              measurement: m,
              latestLabel: latest?.classLabel,
              latestConfidence: latest?.confidence,
            ),
            if (m.isMeasuring) ...[
              const SizedBox(height: AppTheme.spaceMd),
              _WindowProgress(measurement: m),
            ],
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Cumulative dose'),
            DoseBar(dose: dashboard.dose, limitDb: limit),
            if (dashboard.readings.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spaceLg),
              const SectionLabel('Recent'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spaceMd,
                    vertical: AppTheme.spaceXs,
                  ),
                  child: Column(
                    children: [
                      for (final (i, r)
                          in dashboard.readings.take(3).indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ReadingTile(
                          reading: r,
                          thresholdDbA: limit,
                          isPending: dashboard.isPending(r),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (m.lastWindow?.isClipped ?? false) ...[
              const SizedBox(height: AppTheme.spaceMd),
              const MessageBanner(
                message:
                    'The last minute was louder than the microphone can '
                    'measure, so its reading is a lower limit.',
              ),
            ],
            if (m.errorMessage != null) ...[
              const SizedBox(height: AppTheme.spaceMd),
              MessageBanner(message: m.errorMessage),
            ],
            const SizedBox(height: AppTheme.spaceLg),
            m.isMeasuring
                ? OutlinedButton(
                    onPressed: m.stop,
                    child: const Text('Stop monitoring'),
                  )
                : FilledButton(
                    onPressed: m.status == MeasurementStatus.starting
                        ? null
                        : m.start,
                    child: const Text('Start monitoring'),
                  ),
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              m.calibration.source == CalibrationSource.measured
                  ? 'Calibrated for this phone.'
                  : 'Not yet calibrated for this phone: levels use Android\u2019s '
                        'nominal microphone sensitivity and may be several '
                        'decibels out.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.onSurfaceMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Progress to the next saved reading, and whether measuring continues with the screen off.
class _WindowProgress extends StatelessWidget {
  const _WindowProgress({required this.measurement});

  final MeasurementViewModel measurement;

  @override
  Widget build(BuildContext context) {
    final m = measurement;
    final total = m.window.inSeconds;
    final elapsed = m.elapsedInWindow.inSeconds.clamp(0, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: elapsed / total,
          minHeight: 4,
          backgroundColor: AppTheme.surfaceContainer,
          semanticsLabel: 'Progress to the next saved reading',
          semanticsValue: '$elapsed of $total seconds',
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          [
            'Next reading saved in ${total - elapsed} s',
            '${m.windowsSent} saved',
            if (m.windowsFailed > 0) '${m.windowsFailed} not saved',
          ].join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: m.windowsFailed > 0
                ? AppTheme.error
                : AppTheme.onSurfaceMuted,
            fontSize: 13,
          ),
        ),
        Text(
          m.measuresInBackground
              ? 'Keeps measuring with the screen off.'
              : 'Measuring only while NoiseSense is open on screen.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 13),
        ),
      ],
    );
  }
}

/// The wireframe's "Source: Road traffic 87%" chip.
class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.measurement,
    required this.latestLabel,
    required this.latestConfidence,
  });

  final MeasurementViewModel measurement;
  final String? latestLabel;
  final double? latestConfidence;

  @override
  Widget build(BuildContext context) {
    final live = measurement.lastSource;
    final label = live?.label ?? latestLabel;
    final confidence = live == null ? latestConfidence : live.confidence;
    if (label == null) return const SizedBox.shrink();

    final text = confidence == null
        ? 'Source: ${Formatters.classLabel(label)}'
        : 'Source: ${Formatters.classLabel(label)} '
              '${Formatters.confidence(confidence)}';
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spaceMd),
      child: Center(
        child: Semantics(
          label: confidence == null
              ? 'Main noise source: ${Formatters.classLabel(label)}'
              : 'Main noise source: ${Formatters.classLabel(label)}, model '
                    'score ${Formatters.confidence(confidence)}',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spaceMd,
              vertical: AppTheme.spaceXs + 2,
            ),
            decoration: const ShapeDecoration(
              color: AppTheme.primary,
              shape: StadiumBorder(),
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.onPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
