import 'dart:math' as math;
import 'dart:typed_data';

import 'a_weighting_filter.dart';
import 'microphone_calibration.dart';

/// The result of one complete measurement window.
class MeasuredWindow {
  const MeasuredWindow({
    required this.start,
    required this.duration,
    required this.laeqDb,
    required this.maxFastDb,
    required this.clippedSamples,
  });

  /// Window start time in UTC, derived from the sample count.
  final DateTime start;

  final Duration duration;

  /// A-weighted equivalent continuous level over the window.
  final double laeqDb;

  /// Approximate maximum 125 ms ("fast") level, in dB(A).
  final double maxFastDb;

  /// Number of clipped samples; clipping makes [laeqDb] a lower bound.
  final int clippedSamples;

  bool get isClipped => clippedSamples > 0;
}

/// Output from one call to [LevelMeter.process].
class MeterOutput {
  const MeterOutput(this.liveLevelsDb, this.windows);

  static const empty = MeterOutput([], []);

  /// One-second A-weighted levels for display.
  final List<double> liveLevelsDb;

  /// Windows completed during this call.
  final List<MeasuredWindow> windows;
}

/// Turns audio samples into A-weighted levels without retaining audio.
class LevelMeter {
  LevelMeter({
    required this.sampleRate,
    required this.calibration,
    required DateTime startedAt,
    this.window = const Duration(minutes: 1),
    this.liveInterval = const Duration(seconds: 1),
    this.fastBlock = const Duration(milliseconds: 125),
  }) : _startedAt = startedAt.toUtc(),
       _filter = AWeightingFilter(sampleRate),
       _windowLength = _samplesIn(window, sampleRate),
       _liveLength = _samplesIn(liveInterval, sampleRate),
       _blockLength = _samplesIn(fastBlock, sampleRate);

  final int sampleRate;
  final MicrophoneCalibration calibration;
  final Duration window;
  final Duration liveInterval;
  final Duration fastBlock;

  final DateTime _startedAt;
  final AWeightingFilter _filter;
  final int _windowLength;
  final int _liveLength;
  final int _blockLength;

  int _windowIndex = 0;
  double _windowSum = 0;
  int _windowCount = 0;
  double _liveSum = 0;
  int _liveCount = 0;
  double _blockSum = 0;
  int _blockCount = 0;
  double _blockMaxMeanSquare = 0;
  int _clipped = 0;

  /// Time analysed in the current window.
  Duration get elapsedInWindow =>
      Duration(microseconds: (_windowCount * 1e6 / sampleRate).round());

  /// Analyses the next run of samples.
  MeterOutput process(Int16List samples) {
    if (samples.isEmpty) return MeterOutput.empty;
    final live = <double>[];
    final windows = <MeasuredWindow>[];

    for (final sample in samples) {
      if (sample == 32767 || sample == -32768) _clipped++;

      final y = _filter.process(sample / 32768.0);
      final energy = y * y;
      _windowSum += energy;
      _windowCount++;
      _liveSum += energy;
      _liveCount++;
      _blockSum += energy;
      _blockCount++;

      if (_liveCount == _liveLength) {
        live.add(calibration.levelDb(_liveSum / _liveCount));
        _liveSum = 0;
        _liveCount = 0;
      }

      // Close a block at window boundaries so it does not straddle windows.
      final windowComplete = _windowCount == _windowLength;
      if (_blockCount == _blockLength || windowComplete) {
        _blockMaxMeanSquare = math.max(
          _blockMaxMeanSquare,
          _blockSum / _blockCount,
        );
        _blockSum = 0;
        _blockCount = 0;
      }

      if (windowComplete) {
        windows.add(_closeWindow());
      }
    }
    return MeterOutput(live, windows);
  }

  MeasuredWindow _closeWindow() {
    final startOffset = Duration(
      microseconds: (_windowIndex * _windowLength * 1e6 / sampleRate).round(),
    );
    final result = MeasuredWindow(
      start: _startedAt.add(startOffset),
      duration: window,
      laeqDb: calibration.levelDb(_windowSum / _windowCount),
      maxFastDb: calibration.levelDb(_blockMaxMeanSquare),
      clippedSamples: _clipped,
    );
    _windowIndex++;
    _windowSum = 0;
    _windowCount = 0;
    _blockMaxMeanSquare = 0;
    _clipped = 0;
    return result;
  }

  static int _samplesIn(Duration d, int sampleRate) {
    final n = (d.inMicroseconds * sampleRate / 1e6).round();
    if (n < 1) {
      throw ArgumentError.value(d, 'duration', 'is shorter than one sample');
    }
    return n;
  }
}
