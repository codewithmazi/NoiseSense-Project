import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/acoustics/a_weighting_filter.dart';

/// Nominal A-weighting values from the IEC 61672-1 table, in dB, rounded to 0.1 dB as published.
final Map<double, double> _iecNominal = {
  31.5: -39.4,
  63: -26.2,
  125: -16.1,
  250: -8.6,
  500: -3.2,
  1000: 0.0,
  2000: 1.2,
  4000: 1.0,
  8000: -1.1,
  16000: -6.6,
};

/// Measured gain of [filter] at [frequency], using a sine wave.
double _measuredGainDb(AWeightingFilter filter, double frequency) {
  final rate = filter.sampleRate;
  filter.reset();
  // Let the transient decay before measuring.
  final settle = rate ~/ 2;
  // Measure over a whole number of cycles of the lowest test frequency.
  final measure = rate * 2;
  var inSum = 0.0, outSum = 0.0;
  for (var n = 0; n < settle + measure; n++) {
    final x = math.sin(2 * math.pi * frequency * n / rate);
    final y = filter.process(x);
    if (n >= settle) {
      inSum += x * x;
      outSum += y * y;
    }
  }
  return 10 * math.log(outSum / inSum) / math.ln10;
}

void main() {
  group('reference curve', () {
    test('the analogue formula reproduces the IEC 61672-1 nominal table', () {
      // Checks the reference table first.
      _iecNominal.forEach((nominal, expected) {
        final n = (10 * math.log(nominal / 1000) / math.ln10).round();
        final exact = 1000 * math.pow(10, n / 10).toDouble();
        expect(
          AWeightingFilter.analogueResponseDb(exact),
          closeTo(expected, 0.05),
          reason: '$nominal Hz (exact ${exact.toStringAsFixed(2)} Hz)',
        );
      });
    });

    test('using the nominal label instead of the exact frequency is wrong '
        'by more than the table rounding at 31.5 Hz', () {
      // The negative case for the test above, keeping the finding on record.
      expect(
        (AWeightingFilter.analogueResponseDb(31.5) - -39.4).abs(),
        greaterThan(0.05),
      );
    });
  });

  for (final rate in [44100, 48000]) {
    group('digital filter at $rate Hz', () {
      final filter = AWeightingFilter(rate);

      test('is exactly 0 dB at 1 kHz, by definition', () {
        expect(filter.responseDb(1000), closeTo(0, 1e-9));
      });

      test('matches the analogue curve within 0.1 dB from 20 Hz to 4 kHz', () {
        // Within 0.1 dB up to 4 kHz, the band the CDD requires to be flat.
        final errors = <String, double>{};
        for (final f in <double>[
          20,
          31.5,
          63,
          125,
          250,
          500,
          1000,
          2000,
          4000,
        ]) {
          errors['$f'] =
              filter.responseDb(f) - AWeightingFilter.analogueResponseDb(f);
        }
        _report(
          'Bilinear error vs analogue, $rate Hz (20 Hz to 4 kHz)',
          errors,
        );
        for (final e in errors.entries) {
          expect(e.value.abs(), lessThan(0.1), reason: '${e.key} Hz');
        }
      });

      test('reports its high-frequency error rather than hiding it', () {
        // Above 4 kHz the bilinear transform warps frequency more.
        final errors = <String, double>{};
        for (final f in <double>[6300, 8000, 10000, 12500, 16000]) {
          errors['$f'] =
              filter.responseDb(f) - AWeightingFilter.analogueResponseDb(f);
        }
        _report('Bilinear error vs analogue, $rate Hz (above 4 kHz)', errors);
        expect(errors['10000.0']!, lessThan(0));
        expect(errors['10000.0']!.abs(), lessThan(3));
      });

      test('the implementation behaves as its coefficients predict', () {
        // The tests above evaluate the transfer function on paper.
        for (final f in <double>[63, 250, 1000, 4000]) {
          expect(
            _measuredGainDb(filter, f),
            closeTo(filter.responseDb(f), 0.02),
            reason: '$f Hz',
          );
        }
      });
    });
  }

  test('a sample rate too low for the curve is rejected', () {
    // At 16 kHz the 12.2 kHz pole lies above Nyquist.
    expect(() => AWeightingFilter(16000), throwsArgumentError);
  });

  test('reset clears the filter memory', () {
    final filter = AWeightingFilter(48000);
    for (var i = 0; i < 1000; i++) {
      filter.process(1.0);
    }
    filter.reset();
    expect(filter.process(0.0), 0.0);
  });
}

void _report(String heading, Map<String, double> errors) {
  final lines = errors.entries
      .map(
        (e) =>
            '  ${e.key.padLeft(8)} Hz  ${e.value >= 0 ? '+' : ''}${e.value.toStringAsFixed(3)} dB',
      )
      .join('\n');
  // ignore: avoid_print
  print('\n$heading\n$lines\n');
}
