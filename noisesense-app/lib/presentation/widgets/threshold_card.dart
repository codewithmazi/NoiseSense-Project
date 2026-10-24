import 'package:flutter/material.dart';

import '../../domain/models/exposure_settings.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';

/// Control for the user's alert threshold (603: FR-05).
class ThresholdCard extends StatefulWidget {
  const ThresholdCard({
    super.key,
    required this.settings,
    required this.isSaving,
    required this.onChanged,
  });

  /// Current settings, or null while they are loading.
  final ExposureSettings? settings;

  final bool isSaving;

  /// Called when the user finishes dragging, not during the drag.
  final ValueChanged<double> onChanged;

  @override
  State<ThresholdCard> createState() => _ThresholdCardState();
}

class _ThresholdCardState extends State<ThresholdCard> {
  /// The value under the user's finger.
  double? _dragging;

  @override
  void didUpdateWidget(ThresholdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Drop the local value once the service confirms the change.
    if (oldWidget.settings?.thresholdDbA != widget.settings?.thresholdDbA) {
      _dragging = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    if (settings == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppTheme.spaceLg),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final value = _dragging ?? settings.thresholdDbA;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Alert me above',
                    style: TextStyle(
                      color: AppTheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.isSaving)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    Formatters.threshold(value),
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            Slider(
              value: value.clamp(
                ExposureSettings.minThresholdDbA,
                ExposureSettings.maxThresholdDbA,
              ),
              min: ExposureSettings.minThresholdDbA,
              max: ExposureSettings.maxThresholdDbA,
              // One division per decibel.
              divisions:
                  (ExposureSettings.maxThresholdDbA -
                          ExposureSettings.minThresholdDbA)
                      .round(),
              // Value read out to screen readers while dragging.
              label: Formatters.threshold(value),
              semanticFormatterCallback: (v) => '${v.round()} decibels',
              onChanged: widget.isSaving
                  ? null
                  : (v) => setState(() => _dragging = v.roundToDouble()),
              // Saved on release rather than on change.
              onChangeEnd: widget.isSaving ? null : widget.onChanged,
            ),
            // The default is labelled as a default.
            Text(
              settings.isDefault
                  ? 'Currently using the default level.'
                  : 'Your chosen level.',
              style: const TextStyle(
                color: AppTheme.onSurfaceMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
