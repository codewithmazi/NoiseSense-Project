import 'package:flutter/material.dart';

import '../../domain/models/noise_reading.dart';
import '../exposure_tone.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';

/// Bar chart of recent readings, oldest on the left, after the History
/// wireframe.
///
/// Each bar is one reading's LAeq, coloured by exposure tone, on a fixed
/// 30 to 100 dB(A) axis so charts from different days are comparable. The
/// threshold is drawn as a line, so "which minutes went over" can be read
/// without counting.
///
/// The chart is an overview; the list beneath it carries the exact values.
/// For a screen reader it is summarised in one sentence (range and how many
/// readings were over) rather than read bar by bar, which at 100 bars would
/// be unusable.
class LevelChart extends StatelessWidget {
  const LevelChart({super.key, required this.readings, required this.limitDb});

  /// Newest first, as the rest of the app holds them.
  final List<NoiseReading> readings;
  final double? limitDb;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) return const SizedBox.shrink();
    final ordered = readings.reversed.toList();
    final levels = [for (final r in ordered) r.laeq ?? r.dbA];
    final limit = limitDb;
    final over = limit == null ? 0 : levels.where((l) => l >= limit).length;
    final lo = levels.reduce((a, b) => a < b ? a : b);
    final hi = levels.reduce((a, b) => a > b ? a : b);

    return Semantics(
      label:
          'Chart of ${levels.length} readings from '
          '${Formatters.timestamp(ordered.first.timestamp)} to '
          '${Formatters.timestamp(ordered.last.timestamp)}, ranging from '
          '${Formatters.levelValue(lo)} to ${Formatters.levelValue(hi)} '
          'decibels. $over above your limit.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _BarsPainter(levels: levels, limitDb: limit),
            ),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          // Each label takes half the width and wraps within it. Found by the
          // large-text test: readings from an earlier day carry a date
          // ("16 Oct, 14:50"), and at 2x text two of those side by side
          // overflowed by 299 px.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  Formatters.timestamp(ordered.first.timestamp),
                  style: _axis,
                ),
              ),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(
                child: Text(
                  Formatters.timestamp(ordered.last.timestamp),
                  textAlign: TextAlign.end,
                  style: _axis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _axis = TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12);
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.levels, required this.limitDb});

  final List<double> levels;
  final double? limitDb;

  static const double _minDb = 30;
  static const double _maxDb = 100;

  double _y(double db, double height) =>
      height * (1 - ((db - _minDb) / (_maxDb - _minDb)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / levels.length;
    final gap = slot > 4 ? 1.5 : 0.0;
    final paint = Paint();
    for (var i = 0; i < levels.length; i++) {
      paint.color = ExposureTone.of(levels[i], limitDb).colour;
      final top = _y(levels[i], size.height);
      canvas.drawRect(
        Rect.fromLTRB(
          i * slot + gap / 2,
          top,
          (i + 1) * slot - gap / 2,
          size.height,
        ),
        paint,
      );
    }

    final limit = limitDb;
    if (limit != null) {
      final y = _y(limit, size.height);
      final line = Paint()
        ..color = AppTheme.onSurfaceMuted
        ..strokeWidth = 1.5;
      // Dashed, so the line is not mistaken for the top of a bar.
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), line);
      }
    }

    final baseline = Paint()
      ..color = AppTheme.outlineSubtle
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      baseline,
    );
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.levels != levels || old.limitDb != limitDb;
}
