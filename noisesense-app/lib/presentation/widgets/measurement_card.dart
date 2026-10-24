import 'package:flutter/material.dart';

import '../../domain/acoustics/microphone_calibration.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';
import '../view_models/measurement_view_model.dart';
import 'message_banner.dart';

/// Start and stop live measurement, and see what the microphone hears.
class MeasurementCard extends StatelessWidget {
  const MeasurementCard({super.key, required this.viewModel});

  final MeasurementViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final vm = viewModel;
        final live = vm.liveLevelDb;
        final windowSeconds = vm.window.inSeconds;
        final elapsed = vm.elapsedInWindow.inSeconds.clamp(0, windowSeconds);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      vm.isMeasuring ? Icons.mic : Icons.mic_none,
                      color: vm.isMeasuring
                          ? AppTheme.primary
                          : AppTheme.onSurfaceMuted,
                      semanticLabel: '',
                    ),
                    const SizedBox(width: AppTheme.spaceSm),
                    Text(
                      vm.isMeasuring ? 'Measuring' : 'Measure now',
                      style: const TextStyle(
                        color: AppTheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (vm.isMeasuring) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  // Announced politely to screen readers as it changes.
                  Semantics(
                    liveRegion: true,
                    label: live == null
                        ? 'Listening'
                        : 'Current level ${Formatters.levelValue(live)} '
                              'decibels A-weighted',
                    excludeSemantics: true,
                    child: Text(
                      live == null ? '\u2026' : Formatters.level(live),
                      style: const TextStyle(
                        color: AppTheme.onSurface,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceSm),
                  LinearProgressIndicator(
                    value: elapsed / windowSeconds,
                    semanticsLabel: 'Progress to the next saved reading',
                    semanticsValue: '$elapsed of $windowSeconds seconds',
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  Text(
                    'Next reading saved in ${windowSeconds - elapsed} s',
                    style: const TextStyle(
                      color: AppTheme.onSurfaceMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  // States the coverage actually in force.
                  Text(
                    vm.measuresInBackground
                        ? 'Keeps measuring with the screen off. Stop it here '
                              'or from the notification.'
                        : 'Measuring only while NoiseSense is open on '
                              'screen.',
                    style: const TextStyle(
                      color: AppTheme.onSurfaceMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: AppTheme.spaceSm),
                  Text(
                    'Readings are saved once a minute, including with the '
                    'screen off. Sound is analysed on your phone and never '
                    'recorded.',
                    style: const TextStyle(
                      color: AppTheme.onSurfaceMuted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
                if (vm.windowsSent > 0 || vm.windowsFailed > 0) ...[
                  const SizedBox(height: AppTheme.spaceSm),
                  Text(
                    [
                      '${vm.windowsSent} saved',
                      if (vm.windowsFailed > 0)
                        '${vm.windowsFailed} could not be saved',
                    ].join(' \u00b7 '),
                    style: TextStyle(
                      color: vm.windowsFailed > 0
                          ? AppTheme.error
                          : AppTheme.onSurfaceMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (vm.lastWindow?.isClipped ?? false) ...[
                  const SizedBox(height: AppTheme.spaceSm),
                  const MessageBanner(
                    message:
                        'The last minute was louder than the microphone can '
                        'measure, so its reading is a lower limit.',
                  ),
                ],
                if (vm.errorMessage != null) ...[
                  const SizedBox(height: AppTheme.spaceSm),
                  MessageBanner(message: vm.errorMessage),
                ],
                const SizedBox(height: AppTheme.spaceMd),
                vm.isMeasuring
                    ? OutlinedButton(
                        onPressed: vm.stop,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(
                            AppTheme.minTouchTarget,
                          ),
                        ),
                        child: const Text('Stop'),
                      )
                    : FilledButton(
                        onPressed: vm.status == MeasurementStatus.starting
                            ? null
                            : vm.start,
                        child: const Text('Start measuring'),
                      ),
                const SizedBox(height: AppTheme.spaceSm),
                Text(
                  vm.calibration.source == CalibrationSource.measured
                      ? 'Calibrated for this phone.'
                      : 'Not yet calibrated for this phone: levels use '
                            'Android\u2019s nominal microphone sensitivity '
                            'and may be several decibels out.',
                  style: const TextStyle(
                    color: AppTheme.onSurfaceMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
