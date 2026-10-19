import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/acoustics/decimator.dart';

Float32List _sine(double f, int n, {int rate = 48000}) => Float32List.fromList([
  for (var i = 0; i < n; i++) math.sin(2 * math.pi * f * i / rate),
]);

double _rms(Float32List x, {int skip = 0}) {
  var s = 0.0;
  for (var i = skip; i < x.length; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / (x.length - skip));
}

void main() {
  test('output has a third of the input samples', () {
    final out = Decimator().process(Float32List(48000));
    expect(out.length, 16000);
  });

  test('passes speech and traffic frequencies essentially unchanged', () {
    final d = Decimator();
    final report = <String>[];
    for (final f in <double>[100, 500, 1000, 3000, 6000]) {
      final db = d.responseDb(f);
      report.add(
        '  ${f.toStringAsFixed(0).padLeft(6)} Hz  ${db.toStringAsFixed(3)} dB',
      );
      expect(db.abs(), lessThan(0.1), reason: '$f Hz');
    }
    // ignore: avoid_print
    print('\nDecimator passband\n${report.join('\n')}\n');
  });

  test('suppresses frequencies that would alias below 8 kHz', () {
    // Anything at or above the new Nyquist (8 kHz) folds back into the band
    // the classifier hears. These are the measured stopband figures.
    final d = Decimator();
    final report = <String>[];
    for (final f in <double>[8000, 9000, 12000, 16000, 20000]) {
      final db = d.responseDb(f);
      report.add(
        '  ${f.toStringAsFixed(0).padLeft(6)} Hz  ${db.toStringAsFixed(1)} dB',
      );
      expect(db, lessThan(f == 8000 ? -40 : -60), reason: '$f Hz');
    }
    // ignore: avoid_print
    print('\nDecimator stopband\n${report.join('\n')}\n');
  });

  test('a real 1 kHz tone keeps its level through the filter', () {
    final out = Decimator().process(_sine(1000, 48000));
    expect(_rms(out, skip: 100), closeTo(1 / math.sqrt2, 0.005));
  });

  test('a real 12 kHz tone is removed rather than folded to 4 kHz', () {
    // The negative case. Plain one-in-three sampling would turn this into a
    // full-strength 4 kHz tone that was never in the room.
    final tone = _sine(12000, 48000);
    final naive = Float32List.fromList([
      for (var i = 0; i < tone.length; i += 3) tone[i],
    ]);
    final filtered = Decimator().process(tone);
    expect(_rms(naive), greaterThan(0.5), reason: 'the aliasing being avoided');
    expect(_rms(filtered, skip: 100), lessThan(0.001));
  });

  test('output does not depend on how input is chunked', () {
    final signal = _sine(440, 4801);
    final whole = Decimator().process(signal);
    final d = Decimator();
    final parts = <double>[];
    for (var i = 0; i < signal.length; i += 7) {
      parts.addAll(
        d.process(
          Float32List.sublistView(signal, i, math.min(i + 7, signal.length)),
        ),
      );
    }
    expect(parts.length, whole.length);
    for (var i = 0; i < whole.length; i++) {
      expect(parts[i], closeTo(whole[i], 1e-6));
    }
  });
}
