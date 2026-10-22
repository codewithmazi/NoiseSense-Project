import 'dart:math' as math;

/// Digital A-weighting filter, normalised to 0 dB at 1 kHz.
class AWeightingFilter {
  AWeightingFilter(this.sampleRate) {
    if (sampleRate <= 2 * f4) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'must exceed ${(2 * f4).ceil()} Hz to represent the A-weighting curve',
      );
    }
    final r1 = _pole(f1);
    final r2 = _pole(f2);
    final r3 = _pole(f3);
    final r4 = _pole(f4);

    _sections = [
      // Low-frequency cut: double pole at f1.
      _Biquad(1, -2, 1, -2 * r1, r1 * r1),
      // Poles at f2 and f3.
      _Biquad(1, -2, 1, -(r2 + r3), r2 * r3),
      // High-frequency roll-off: double pole at f4.
      _Biquad(1, 2, 1, -2 * r4, r4 * r4),
    ];

    // Normalise gain to 0 dB at 1 kHz.
    _gain = 1 / _cascadeMagnitude(1000);
  }

  /// Analogue A-weighting corner frequencies (Hz), per IEC 61672-1.
  static const double f1 = 20.598997;
  static const double f2 = 107.65265;
  static const double f3 = 737.86223;
  static const double f4 = 12194.217;

  final int sampleRate;
  late final List<_Biquad> _sections;
  late final double _gain;

  /// Filters one sample; samples must be supplied in order.
  double process(double sample) {
    var y = sample * _gain;
    for (final section in _sections) {
      y = section.process(y);
    }
    return y;
  }

  /// Clears the filter's state.
  void reset() {
    for (final section in _sections) {
      section.reset();
    }
  }

  /// Filter response at [frequency], in dB.
  double responseDb(double frequency) =>
      20 * _log10(_gain * _cascadeMagnitude(frequency));

  /// Ideal analogue A-weighting response at [frequency], in dB.
  static double analogueResponseDb(double frequency) =>
      20 * _log10(_analogueMagnitude(frequency) / _analogueMagnitude(1000));

  /// Maps an analogue pole to the z-plane via the bilinear transform.
  double _pole(double frequency) {
    final w = 2 * math.pi * frequency;
    final k = 2.0 * sampleRate;
    return (k - w) / (k + w);
  }

  double _cascadeMagnitude(double frequency) {
    final omega = 2 * math.pi * frequency / sampleRate;
    var magnitude = 1.0;
    for (final section in _sections) {
      magnitude *= section.magnitudeAt(omega);
    }
    return magnitude;
  }

  static double _analogueMagnitude(double f) {
    final fSq = f * f;
    final numerator = f4 * f4 * fSq * fSq;
    final denominator =
        (fSq + f1 * f1) *
        math.sqrt((fSq + f2 * f2) * (fSq + f3 * f3)) *
        (fSq + f4 * f4);
    return numerator / denominator;
  }

  static double _log10(double x) => math.log(x) / math.ln10;
}

/// One second-order filter section in transposed direct form II.
class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0, b1, b2, a1, a2;
  double _s1 = 0, _s2 = 0;

  double process(double x) {
    final y = b0 * x + _s1;
    _s1 = b1 * x - a1 * y + _s2;
    _s2 = b2 * x - a2 * y;
    return y;
  }

  void reset() {
    _s1 = 0;
    _s2 = 0;
  }

  /// Magnitude response at normalised angular frequency [omega].
  double magnitudeAt(double omega) {
    final c1 = math.cos(omega), s1 = math.sin(omega);
    final c2 = math.cos(2 * omega), s2 = math.sin(2 * omega);
    final numRe = b0 + b1 * c1 + b2 * c2;
    final numIm = -(b1 * s1 + b2 * s2);
    final denRe = 1 + a1 * c1 + a2 * c2;
    final denIm = -(a1 * s1 + a2 * s2);
    return math.sqrt(
      (numRe * numRe + numIm * numIm) / (denRe * denRe + denIm * denIm),
    );
  }
}
