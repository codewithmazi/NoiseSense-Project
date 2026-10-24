import 'dart:math' as math;
import 'dart:ui';

/// Colour contrast arithmetic from WCAG 2.2.
class Contrast {
  const Contrast._();

  /// Minimum ratio for body text at normal size: WCAG 2.2 SC 1.4.3 (AA).
  static const double aaNormalText = 4.5;

  /// Large-text minimum ratio (18pt, or 14pt bold): SC 1.4.3.
  static const double aaLargeText = 3.0;

  /// Minimum ratio for the visual boundary of a control or a meaningful graphic.
  static const double aaNonText = 3.0;

  /// Relative luminance of [colour], from 0 (black) to 1 (white).
  static double relativeLuminance(Color colour) {
    final r = _linearise(colour.r);
    final g = _linearise(colour.g);
    final b = _linearise(colour.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Contrast ratio between two colours, from 1.0 (identical) to 21.0 (black against white).
  static double ratio(Color a, Color b) {
    if (a.a != 1.0 || b.a != 1.0) {
      throw ArgumentError(
        'Contrast is only defined for opaque colours; composite first.',
      );
    }
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Linearises one sRGB channel already normalised to 0.0-1.0.
  static double _linearise(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}
