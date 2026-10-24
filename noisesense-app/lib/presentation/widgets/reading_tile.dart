import 'package:flutter/material.dart';

import '../../domain/models/noise_reading.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';

/// One row in the history list.
class ReadingTile extends StatelessWidget {
  const ReadingTile({
    super.key,
    required this.reading,
    required this.thresholdDbA,
    this.isPending = false,
  });

  final NoiseReading reading;

  /// Held on this phone and not yet uploaded.
  final bool isPending;

  /// The user's alert level, used only to mark rows that exceeded it.
  final double? thresholdDbA;

  @override
  Widget build(BuildContext context) {
    // LAeq preferred: it is already an energy average.
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
        if (isPending) 'waiting to upload',
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceSm + 2),
        child: Row(
          children: [
            SizedBox(
              // Wide enough for "16 Oct, 20:12" on one line at normal text size.
              width: 112,
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
                        // Confidence always shown with the label.
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
            if (isPending)
              const Padding(
                padding: EdgeInsets.only(right: AppTheme.spaceXs),
                child: Icon(
                  Icons.cloud_upload_outlined,
                  size: 18,
                  color: AppTheme.onSurfaceMuted,
                  semanticLabel: '',
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
