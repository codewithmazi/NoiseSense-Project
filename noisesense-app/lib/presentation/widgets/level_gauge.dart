import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../exposure_tone.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';

/// The Monitor screen's ring gauge, after the hi-fi wireframe.
class LevelGauge extends StatelessWidget {
  const LevelGauge({
    super.key,
    required this.levelDb,
    required this.limitDb,
    required this.caption,
  });

  /// Null when there is nothing to show yet, for example before measuring.
  final double? levelDb;
  final double? limitDb;
  final String caption;

  static const double _minDb = 30;
  static const double _maxDb = 100;

  @override
  Widget build(BuildContext context) {
    final level = levelDb;
    final tone = level == null ? null : ExposureTone.of(level, limitDb);
    final fraction = level == null
        ? 0.0
        : ((level - _minDb) / (_maxDb - _minDb)).clamp(0.0, 1.0);

    return Semantics(
      label: level == null
          ? 'No live level. $caption'
          : '${Formatters.levelValue(level)} decibels A-weighted, '
                '${tone!.label.toLowerCase()}. $caption',
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox.square(
            dimension: 180,
            child: CustomPaint(
              painter: _RingPainter(
                fraction: fraction,
                colour: tone?.colour ?? AppTheme.outlineSubtle,
              ),
              child: Center(
                child: Text(
                  level == null ? '–' : level.round().toString(),
                  style: const TextStyle(
                    color: AppTheme.onSurface,
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.onSurfaceMuted,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.colour});

  final double fraction;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    // A 270° arc open at the bottom, so an empty gauge still reads as a dial.
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;

    final track = Paint()
      ..color = AppTheme.surfaceContainer
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, start, sweep, false, track);

    if (fraction > 0) {
      final fill = Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcRect, start, sweep * fraction, false, fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.colour != colour;
}
