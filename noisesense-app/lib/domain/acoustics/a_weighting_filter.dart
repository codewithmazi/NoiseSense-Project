import 'dart:math' as math;

/// Digital A-weighting filter.
///
/// A-weighting approximates the ear's reduced sensitivity to low and very high
/// frequencies, which is why environmental noise limits, including the WHO
/// guideline values this app compares against, are stated in dB(A). Without it,
/// a phone would report the rumble of a bus engine as louder than the ear
/// perceives it, and overstate exposure in exactly the traffic settings the app
/// exists to measure.
///
/// ## Derivation
///
/// IEC 61672-1 defines A-weighting as an analogue transfer function with four
/// zeros at s = 0 and poles at four corner frequencies: a double pole at f1, single
/// poles at f2 and f3, and a double pole at f4. This class converts that
/// function to a digital filter with the bilinear transform, mapping each
/// analogue pole at s = -w to z = (2fs - w) / (2fs + w). The four zeros at s = 0
/// map to z = 1, and the two surplus zeros at infinity map to z = -1, the Nyquist
/// frequency.
///
/// The result is implemented as three second-order sections in cascade rather
/// than as one sixth-order polynomial. A single high-order recursion is
/// numerically fragile: its coefficients are sums of products of poles close to
/// z = 1, and rounding error in them moves the poles. Each section here has
/// coefficients that are exactly representable functions of one or two poles.
/// Each pair of zeros at z = 1 is placed with the low-frequency poles it nearly
/// cancels, which keeps the intermediate signal well scaled.
///
/// ## Known limitation
///
/// The bilinear transform compresses the frequency axis towards Nyquist, so the
/// response falls away from the analogue ideal at high frequencies. The size of
/// that error is measured, not assumed, in `a_weighting_filter_test.dart`. It is
/// tolerable here for a reason specific to phones: the Android CDD only asks for
/// the microphone itself to be flat within ±3 dB between 100 Hz and 4 kHz, and
/// allows ±30 dB above 4 kHz. Above 4 kHz the hardware's uncertainty is an order
/// of magnitude larger than this filter's.
class AWeightingFilter {
  AWeightingFilter(this.sampleRate) {
    if (sampleRate <= 2 * f4) {
      // Below this the f4 pole lies above Nyquist and cannot be represented.
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
      // Two zeros at DC with the double pole at f1: a steep low cut.
      _Biquad(1, -2, 1, -2 * r1, r1 * r1),
      // Two zeros at DC with the poles at f2 and f3.
      _Biquad(1, -2, 1, -(r2 + r3), r2 * r3),
      // Two zeros at Nyquist with the double pole at f4: the high roll-off.
      _Biquad(1, 2, 1, -2 * r4, r4 * r4),
    ];

    // A-weighting is defined as 0 dB at 1 kHz, so the gain is whatever makes
    // the cascade's response exactly 1 there.
    _gain = 1 / _cascadeMagnitude(1000);
  }

  /// Corner frequencies of the analogue A-weighting function, in hertz, as
  /// given in IEC 61672-1.
  static const double f1 = 20.598997;
  static const double f2 = 107.65265;
  static const double f3 = 737.86223;
  static const double f4 = 12194.217;

  final int sampleRate;
  late final List<_Biquad> _sections;
  late final double _gain;

  /// Filters one sample. Samples must be supplied in order: the filter has
  /// memory, so each output depends on the samples before it.
  double process(double sample) {
    var y = sample * _gain;
    for (final section in _sections) {
      y = section.process(y);
    }
    return y;
  }

  /// Clears the filter's memory, as if no samples had been seen.
  void reset() {
    for (final section in _sections) {
      section.reset();
    }
  }

  /// This filter's gain at [frequency], in dB, evaluated from its coefficients.
  double responseDb(double frequency) =>
      20 * _log10(_gain * _cascadeMagnitude(frequency));

  /// The ideal analogue A-weighting at [frequency], in dB, normalised to 0 dB
  /// at 1 kHz. This is the reference the digital filter is tested against.
  static double analogueResponseDb(double frequency) =>
      20 * _log10(_analogueMagnitude(frequency) / _analogueMagnitude(1000));

  /// Bilinear mapping of an analogue pole at s = -2*pi*f to the z-plane.
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

/// One second-order section, in transposed direct form II.
///
/// Transposed direct form II needs two state variables rather than four, and
/// in floating point it is the better-behaved of the direct forms because it
/// does not pass the input through the high-gain recursive part before the
/// zeros attenuate it.
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

  /// |H(e^{j omega})| for this section.
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
