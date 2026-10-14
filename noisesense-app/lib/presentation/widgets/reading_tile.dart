import 'package:flutter/material.dart';

import '../../domain/models/noise_reading.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';

/// One row in the history list.
///
/// Each row is announced to a screen reader as a single sentence rather than
/// as four adjacent fragments. Without that, navigating the list by swipe
/// produces "14:32", "67.4", "dB(A)", "Road traffic", "82%" as five separate
/// stops, which is technically labelled and practically unusable.
class ReadingTile extends StatelessWidget {
  const ReadingTile({
    super.key,
    required this.reading,
    required this.thresholdDbA,
  });

  final NoiseReading reading;

  /// The user's alert level, used only to mark rows that exceeded it.
  final double? thresholdDbA;

  @override
  Widget build(BuildContext context) {
    // LAeq is preferred when present because it is already an energy average
    // over the window, so it describes the whole window rather than a moment
    // within it. dB(A) is the fallback.
    final level = reading.laeq ?? reading.dbA;
    final threshold = thresholdDbA;
    final isOver = threshold != null && level >= threshold;
    final label = reading.classLabel;
    final confidence = reading.confidence;

    return Semantics(
      label: [
        Formatters.timestamp(reading.timestamp),
        '${Formatters.levelValue(level)} decibels A-weighted',
        if (label != null) Formatters.classLabel(label),
        if (label != null && confidence != null)
          '${Formatters.confidence(confidence)} confidence',
        if (isOver) 'above your alert level',
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceSm + 2),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(
                Formatters.timestamp(reading.timestamp),
                style: const TextStyle(
                  color: AppTheme.onSurfaceMuted,
                  fontSize: 14,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Formatters.level(level),
                    style: TextStyle(
                      color: isOver ? AppTheme.error : AppTheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (label != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        // The confidence is shown with the label, never the
                        // label alone. An on-device classifier running on
                        // quantised weights is often wrong, and presenting
                        // "Road traffic" as a bare fact would overstate what
                        // the model actually knows. Experiment M7 reports the
                        // confusion matrix behind this caveat.
                        confidence == null
                            ? Formatters.classLabel(label)
                            : '${Formatters.classLabel(label)} '
                                  '· ${Formatters.confidence(confidence)} confident',
                        style: const TextStyle(
                          color: AppTheme.onSurfaceMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (isOver)
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppTheme.error,
                semanticLabel: '',
              ),
          ],
        ),
      ),
    );
  }
}
