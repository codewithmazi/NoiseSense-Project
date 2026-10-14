import 'package:flutter/material.dart';

import '../../domain/models/exposure_settings.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';

/// Control for the user's alert threshold (603: FR-05).
///
/// The fixed 70 dB(A) trigger in the 602 back end is replaced here by a value
/// the user owns. The justification is not just preference: a threshold useful
/// to someone working beside a motorway is useless to someone tracking their
/// bedroom, and a system that alerts constantly trains its user to ignore it.
///
/// A slider is used rather than a text field because the value is approximate
/// and bounded, and dragging communicates the range without the user having to
/// discover it by being rejected. The exact figure is shown alongside, so the
/// imprecision of dragging does not hide what has actually been selected.
///
/// Discrete steps of 1 dB are enforced, matching the resolution the figure is
/// displayed at. A continuous slider would let the user select 68.3 dB(A) and
/// then be shown "68 dB(A)", which is a small lie about what was saved.
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
  ///
  /// Held locally so the slider and its label track the drag at once, while
  /// the saved value stays whatever the service last confirmed. Driving the
  /// slider from the saved value alone would make it lag behind the finger by
  /// a network round trip, which feels broken.
  double? _dragging;

  @override
  void didUpdateWidget(ThresholdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Once the service confirms a change, drop the local value so the card
    // shows the authoritative one again.
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
              // One division per decibel, so every selectable value is one
              // that can be displayed exactly.
              divisions:
                  (ExposureSettings.maxThresholdDbA -
                          ExposureSettings.minThresholdDbA)
                      .round(),
              // Read out as the user drags, so the value is available without
              // sight of the label.
              label: Formatters.threshold(value),
              semanticFormatterCallback: (v) => '${v.round()} decibels',
              onChanged: widget.isSaving
                  ? null
                  : (v) => setState(() => _dragging = v.roundToDouble()),
              // Saved on release rather than on change. Dragging across the
              // range emits dozens of values, and sending each one would be
              // dozens of writes for one decision. This matters in the
              // Learner Lab, where Lambda is capped at 10 concurrent
              // executions.
              onChangeEnd: widget.isSaving ? null : widget.onChanged,
            ),
            // The default is labelled as a default, rather than presented as
            // though the user had chosen it. Otherwise there is no way to
            // tell "I picked 70" from "nobody has picked anything".
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
