import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../domain/acoustics/level_meter.dart';
import '../../domain/acoustics/microphone_calibration.dart';
import '../../domain/acoustics/pcm_source.dart';
import '../../domain/models/noise_reading.dart';

enum MeasurementStatus {
  idle,
  starting,
  measuring,

  /// The user refused microphone access. Distinct from [failed] because the
  /// remedy is different: a setting the user controls, not a retry.
  permissionDenied,
  failed,
}

/// Runs live measurement and hands each finished window on as a reading.
///
/// Measurement happens only while the app is in the foreground. Since Android
/// 9, an app in the background receives silence from the microphone rather
/// than an error. Carrying on would record a stream of falsely quiet windows,
/// which would understate exposure: for a health tool, the dangerous direction
/// to be wrong in. So measuring stops when the app is backgrounded, and the
/// unfinished window is discarded rather than reported as a short one.
/// Background measurement needs a foreground service, which is a separate
/// piece of work.
class MeasurementViewModel extends ChangeNotifier {
  MeasurementViewModel({
    required this._source,
    required this._onReading,
    MicrophoneCalibration? calibration,
    this.window = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : calibration = calibration ?? MicrophoneCalibration.androidCddNominal,
       _clock = clock ?? DateTime.now;

  final PcmSource _source;
  final Future<bool> Function(NoiseReading reading) _onReading;
  final DateTime Function() _clock;
  final Duration window;
  final MicrophoneCalibration calibration;

  MeasurementStatus _status = MeasurementStatus.idle;
  LevelMeter? _meter;
  StreamSubscription<Int16List>? _subscription;
  double? _liveLevelDb;
  Duration _elapsed = Duration.zero;
  MeasuredWindow? _lastWindow;
  int _windowsSent = 0;
  int _windowsFailed = 0;
  String? _errorMessage;
  bool _disposed = false;

  MeasurementStatus get status => _status;
  bool get isMeasuring => _status == MeasurementStatus.measuring;

  /// The most recent one-second level, for display only.
  double? get liveLevelDb => _liveLevelDb;

  /// Time measured so far in the current window.
  Duration get elapsedInWindow => _elapsed;

  MeasuredWindow? get lastWindow => _lastWindow;
  int get windowsSent => _windowsSent;

  /// Windows measured but not stored. Until the Week 4 outbox exists, a reading
  /// that fails to upload is lost, and this count makes that visible instead of
  /// silent.
  int get windowsFailed => _windowsFailed;

  String? get errorMessage => _errorMessage;

  Future<void> start() async {
    if (_status == MeasurementStatus.starting || isMeasuring) return;
    _setStatus(MeasurementStatus.starting);

    final allowed = await _source.ensurePermission();
    if (_disposed) return;
    if (!allowed) {
      _errorMessage =
          'NoiseSense needs microphone access to measure. You can allow it '
          'in your phone\u2019s settings for this app.';
      _setStatus(MeasurementStatus.permissionDenied);
      return;
    }

    try {
      final stream = await _source.start();
      if (_disposed) {
        await _source.stop();
        return;
      }
      _meter = LevelMeter(
        sampleRate: _source.sampleRate,
        calibration: calibration,
        startedAt: _clock(),
        window: window,
      );
      _liveLevelDb = null;
      _elapsed = Duration.zero;
      _errorMessage = null;
      _subscription = stream.listen(
        _onSamples,
        onError: (Object _) => _fail(),
        onDone: () {
          if (isMeasuring) _fail();
        },
      );
      _setStatus(MeasurementStatus.measuring);
    } on Exception {
      await _fail();
    }
  }

  /// Stops measuring and releases the microphone. The window in progress is
  /// discarded, because a reading must describe the full window it claims.
  Future<void> stop() async {
    await _release();
    if (_disposed) return;
    _setStatus(MeasurementStatus.idle);
  }

  /// Called when the app leaves or returns to the foreground.
  Future<void> onForegroundChanged({required bool inForeground}) async {
    if (!inForeground && isMeasuring) await stop();
  }

  void _onSamples(Int16List samples) {
    final meter = _meter;
    if (meter == null) return;
    final out = meter.process(samples);
    if (out.liveLevelsDb.isNotEmpty) _liveLevelDb = out.liveLevelsDb.last;
    _elapsed = meter.elapsedInWindow;
    for (final w in out.windows) {
      _lastWindow = w;
      _submit(w);
    }
    if (out.liveLevelsDb.isNotEmpty || out.windows.isNotEmpty) {
      notifyListeners();
    }
  }

  Future<void> _submit(MeasuredWindow w) async {
    // laeq carries the energy average used for dose; dbA carries the window's
    // loudest fast block, so a threshold compared against it still responds
    // to peaks.
    final reading = NoiseReading(
      timestamp: w.start,
      dbA: _round1(w.maxFastDb),
      laeq: _round1(w.laeqDb),
    );
    final ok = await _onReading(reading);
    if (_disposed) return;
    if (ok) {
      _windowsSent++;
    } else {
      _windowsFailed++;
    }
    notifyListeners();
  }

  Future<void> _fail() async {
    await _release();
    if (_disposed) return;
    _errorMessage = 'The microphone stopped unexpectedly. Try starting again.';
    _setStatus(MeasurementStatus.failed);
  }

  Future<void> _release() async {
    await _subscription?.cancel();
    _subscription = null;
    _meter = null;
    await _source.stop();
  }

  void _setStatus(MeasurementStatus s) {
    _status = s;
    notifyListeners();
  }

  /// One decimal place: the display precision, and more than an uncalibrated
  /// phone microphone can justify.
  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  @override
  void dispose() {
    _disposed = true;
    // Fire and forget: dispose cannot be async, and the microphone must be
    // released when the user signs out, not left running behind the sign-in
    // screen.
    unawaited(_release());
    super.dispose();
  }
}
