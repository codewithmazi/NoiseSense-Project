import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/acoustics/level_meter.dart';
import 'package:noise_sense/domain/acoustics/microphone_calibration.dart';

const _rate = 48000;
final _t0 = DateTime.utc(2026, 10, 15, 12);

/// A 16-bit sine of the given RMS, in sample units.
Int16List _sine(double frequency, double rms, Duration length) {
  final n = (length.inMicroseconds * _rate / 1e6).round();
  final peak = rms * math.sqrt2;
  return Int16List.fromList([
    for (var i = 0; i < n; i++)
      (peak * math.sin(2 * math.pi * frequency * i / _rate)).round().clamp(
        -32768,
        32767,
      ),
  ]);
}

LevelMeter _meter({Duration window = const Duration(minutes: 1)}) => LevelMeter(
  sampleRate: _rate,
  calibration: MicrophoneCalibration.androidCddNominal,
  startedAt: _t0,
  window: window,
);

void main() {
  group('calibration', () {
    test('the nominal offset follows from the CDD reference point', () {
      // 90 dB SPL at RMS 2500 of 32768: 90 + 22.35 = 112.35 dB.
      expect(
        MicrophoneCalibration.androidCddNominal.offsetDb,
        closeTo(112.35, 0.005),
      );
      expect(
        MicrophoneCalibration.androidCddNominal.source,
        CalibrationSource.nominal,
      );
    });

    test('digital silence has a finite floor, not negative infinity', () {
      final floor = MicrophoneCalibration.androidCddNominal.noiseFloorDb;
      expect(floor.isFinite, isTrue);
      // About -101 dBFS, roughly 11 dB SPL here.
      expect(floor, closeTo(11.2, 0.2));
    });
  });

  group('golden levels', () {
    test('the CDD reference tone reads 90.0 dB(A)', () {
      // The calibration point: 1 kHz at the CDD reference RMS.
      final meter = _meter();
      final out = meter.process(_sine(1000, 2500, const Duration(minutes: 1)));
      expect(out.windows, hasLength(1));
      expect(out.windows.single.laeqDb, closeTo(90.0, 0.05));
    });

    test('a 100 Hz tone at the same RMS reads 19.1 dB lower', () {
      // A-weighting at 100 Hz is -19.1 dB.
      final meter = _meter();
      final out = meter.process(_sine(100, 2500, const Duration(minutes: 1)));
      expect(out.windows.single.laeqDb, closeTo(90.0 - 19.1, 0.1));
    });

    test('doubling the amplitude adds 6.02 dB', () {
      final quiet = _meter()
          .process(_sine(1000, 1000, const Duration(minutes: 1)))
          .windows
          .single
          .laeqDb;
      final loud = _meter()
          .process(_sine(1000, 2000, const Duration(minutes: 1)))
          .windows
          .single
          .laeqDb;
      expect(loud - quiet, closeTo(20 * math.log(2) / math.ln10, 0.01));
    });
  });

  group('windows', () {
    test('a window closes exactly when its samples are complete', () {
      final meter = _meter();
      final almost = meter.process(
        _sine(1000, 2500, const Duration(seconds: 59)),
      );
      expect(almost.windows, isEmpty);
      final rest = meter.process(_sine(1000, 2500, const Duration(seconds: 1)));
      expect(rest.windows, hasLength(1));
    });

    test('start times come from the sample count', () {
      final meter = _meter();
      final out = meter.process(
        _sine(1000, 2500, const Duration(minutes: 2, seconds: 30)),
      );
      expect(out.windows.map((w) => w.start), [
        _t0,
        _t0.add(const Duration(minutes: 1)),
      ]);
      // The half-finished third window is still in progress, not reported.
      expect(meter.elapsedInWindow, const Duration(seconds: 30));
    });

    test('results do not depend on how the audio is chunked', () {
      // Results must not depend on buffer size.
      final signal = _sine(440, 3000, const Duration(seconds: 2));
      List<MeasuredWindow> run(int chunk) {
        final meter = _meter(window: const Duration(seconds: 1));
        final windows = <MeasuredWindow>[];
        for (var i = 0; i < signal.length; i += chunk) {
          windows.addAll(
            meter
                .process(
                  Int16List.sublistView(
                    signal,
                    i,
                    math.min(i + chunk, signal.length),
                  ),
                )
                .windows,
          );
        }
        return windows;
      }

      final whole = run(signal.length);
      for (final chunk in [997, 1]) {
        final other = run(chunk);
        expect(other, hasLength(whole.length));
        for (var i = 0; i < whole.length; i++) {
          expect(other[i].laeqDb, closeTo(whole[i].laeqDb, 1e-9));
          expect(other[i].maxFastDb, closeTo(whole[i].maxFastDb, 1e-9));
          expect(other[i].start, whole[i].start);
        }
      }
    });
  });

  group('energy averaging', () {
    test('one loud second in a quiet minute: LAeq is the energy average', () {
      // 1 s at 94 dB in a silent minute: the energy average is 76.2 dB.
      final loudRms = 2500 * math.pow(10, 4 / 20).toDouble(); // 90 + 4 dB
      final meter = _meter();
      meter.process(_sine(1000, loudRms, const Duration(seconds: 1)));
      final out = meter.process(
        Int16List((59 * _rate)), // zeros
      );
      final w = out.windows.single;
      expect(w.laeqDb, closeTo(94 - 10 * math.log(60) / math.ln10, 0.1));
      expect(w.maxFastDb, closeTo(94, 0.1));
    });

    test('the fast maximum of a steady tone equals its LAeq', () {
      final w = _meter()
          .process(_sine(1000, 2500, const Duration(minutes: 1)))
          .windows
          .single;
      expect(w.maxFastDb, closeTo(w.laeqDb, 0.05));
    });
  });

  group('live display', () {
    test('one live level per second of audio', () {
      final out = _meter().process(
        _sine(1000, 2500, const Duration(seconds: 5)),
      );
      expect(out.liveLevelsDb, hasLength(5));
      // The first second includes the filter settling, so is excluded.
      for (final level in out.liveLevelsDb.skip(1)) {
        expect(level, closeTo(90, 0.05));
      }
    });
  });

  group('clipping', () {
    test('a clipped window is flagged, because its level is a lower bound', () {
      final out = _meter().process(
        _sine(1000, 40000, const Duration(minutes: 1)),
      );
      expect(out.windows.single.isClipped, isTrue);
    });

    test('an unclipped window is not flagged, and the count resets', () {
      final meter = _meter();
      meter.process(_sine(1000, 40000, const Duration(minutes: 1)));
      final next = meter.process(_sine(1000, 2500, const Duration(minutes: 1)));
      expect(next.windows.single.isClipped, isFalse);
    });
  });
}
