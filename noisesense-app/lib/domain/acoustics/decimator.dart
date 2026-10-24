import 'dart:math' as math;
import 'dart:typed_data';

/// Converts 48 kHz audio to 16 kHz using a low-pass FIR filter before decimation.
class Decimator {
  Decimator({
    this.factor = 3,
    int taps = 127,
    double cutoffHz = 7000,
    int inputRate = 48000,
  }) : _taps = _design(taps, cutoffHz / inputRate),
       _history = Float64List(taps);

  final int factor;
  final Float64List _taps;
  final Float64List _history;
  int _write = 0;
  int _phase = 0;

  /// Converts input samples to decimated output samples.
  Float32List process(Float32List input) {
    final out = Float32List(((_phase + input.length) ~/ factor) + 1);
    var n = 0;
    final len = _taps.length;
    for (final x in input) {
      _history[_write] = x;
      _write = (_write + 1) % len;
      _phase++;
      if (_phase == factor) {
        _phase = 0;
        var acc = 0.0;
        var j = _write;
        for (var k = 0; k < len; k++) {
          acc += _taps[k] * _history[j];
          j = j + 1 == len ? 0 : j + 1;
        }
        out[n++] = acc;
      }
    }
    return Float32List.sublistView(out, 0, n);
  }

  void reset() {
    _history.fillRange(0, _history.length, 0);
    _write = 0;
    _phase = 0;
  }

  /// Filter gain at [frequency], in dB.
  double responseDb(double frequency, {int inputRate = 48000}) {
    final w = 2 * math.pi * frequency / inputRate;
    var re = 0.0, im = 0.0;
    for (var k = 0; k < _taps.length; k++) {
      re += _taps[k] * math.cos(w * k);
      im -= _taps[k] * math.sin(w * k);
    }
    return 10 * math.log(re * re + im * im) / math.ln10;
  }

  /// Designs normalised Blackman-windowed sinc low-pass taps.
  static Float64List _design(int n, double fc) {
    final taps = Float64List(n);
    final m = n - 1;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i - m / 2;
      final sinc = t == 0
          ? 2 * fc
          : math.sin(2 * math.pi * fc * t) / (math.pi * t);
      final blackman =
          0.42 -
          0.5 * math.cos(2 * math.pi * i / m) +
          0.08 * math.cos(4 * math.pi * i / m);
      taps[i] = sinc * blackman;
      sum += taps[i];
    }
    for (var i = 0; i < n; i++) {
      taps[i] /= sum;
    }
    return taps;
  }
}
