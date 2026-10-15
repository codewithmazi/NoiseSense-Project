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

  /// When the window began, in UTC, derived from the sample count rather than
  /// the wall clock (see [LevelMeter]).
  final DateTime start;

  final Duration duration;

  /// A-weighted equivalent continuous level over the whole window: the energy
  /// average, which is the quantity cumulative dose is built from.
  final double laeqDb;

  /// The loudest 125 ms within the window, in dB(A).
  ///
  /// 125 ms is the "fast" time constant of IEC 61672-1. A sound level meter's
  /// LAFmax applies an exponential average with that constant; this takes the
  /// maximum of consecutive 125 ms energy averages instead. The two agree for
  /// steady sounds and differ for short impulses, where a block can split an
  /// event across two blocks and under-read it. It is labelled an
  /// approximation for that reason.
  final double maxFastDb;

  /// Samples at the converter's limits. Any clipping means the true level was
  /// higher than the one reported, so [laeqDb] is then a lower bound.
  final int clippedSamples;

  bool get isClipped => clippedSamples > 0;
}

/// What one call to [LevelMeter.process] produced.
class MeterOutput {
  const MeterOutput(this.liveLevelsDb, this.windows);

  static const empty = MeterOutput([], []);

  /// One-second A-weighted levels, for display.
  final List<double> liveLevelsDb;

  /// Windows completed during this call.
  final List<MeasuredWindow> windows;
}

/// Turns a stream of audio samples into A-weighted levels.
///
/// ## Privacy by construction
///
/// Each run of samples is filtered, squared and added to three running sums,
/// and then nothing more is kept. The meter has no sample buffer. Its memory
/// does not grow with the length of the recording, and no audio exists inside it
/// that could be uploaded, stored or reconstructed. That is the FR-03 guarantee
/// that raw audio never leaves the device, expressed as a property of the data
/// structure rather than as a promise in the code that calls it.
///
/// ## Timing from samples, not the clock
///
/// Window start times are computed as [startedAt] plus samples counted divided
/// by the sample rate. The device clock can jump when the network corrects it,
/// whereas the sample count measures exactly the audio that was analysed. The
/// limitation is that audio the platform drops is not counted, so a dropped
/// buffer shifts later windows earlier by its length.
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

  /// Time analysed so far in the current window.
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

      // A block also closes at a window boundary, so no block straddles two
      // windows and every window's maximum comes from its own audio.
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
