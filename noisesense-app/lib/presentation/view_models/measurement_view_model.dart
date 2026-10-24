import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../domain/acoustics/background_keep_alive.dart';
import '../../domain/acoustics/level_meter.dart';
import '../../domain/acoustics/microphone_calibration.dart';
import '../../domain/acoustics/pcm_source.dart';
import '../../domain/acoustics/source_classifier.dart';
import '../../domain/models/noise_reading.dart';

enum MeasurementStatus {
  idle,
  starting,
  measuring,

  /// The user refused microphone access.
  permissionDenied,
  failed,
}

/// Runs live measurement and turns each finished window into a reading.
class MeasurementViewModel extends ChangeNotifier {
  MeasurementViewModel({
    required this._source,
    required this._onReading,
    this._keepAlive = const NoBackgroundKeepAlive(),
    MicrophoneCalibration? calibration,
    this.window = const Duration(minutes: 1),
    DateTime Function()? clock,
    this._loadClassifier,
  }) : calibration = calibration ?? MicrophoneCalibration.androidCddNominal,
       _clock = clock ?? DateTime.now {
    // Stop pressed on the notification, outside the app.
    _stopRequests = _keepAlive.stopRequests.listen((_) {
      if (isMeasuring) stop();
    });
  }

  final BackgroundKeepAlive _keepAlive;
  late final StreamSubscription<void> _stopRequests;
  bool _keepAliveHeld = false;

  /// Whether measurement will continue when the app is not on screen.
  bool get measuresInBackground => _keepAliveHeld;

  bool _backgroundEnabled = true;

  /// The user's choice, from Settings, to allow measuring with the screen off.
  bool get backgroundEnabled => _backgroundEnabled;

  /// Applies immediately if measuring.
  Future<void> setBackgroundEnabled(bool enabled) async {
    if (enabled == _backgroundEnabled) return;
    _backgroundEnabled = enabled;
    if (isMeasuring) {
      if (enabled && !_keepAliveHeld) {
        _keepAliveHeld = await _keepAlive.begin();
      } else if (!enabled && _keepAliveHeld) {
        _keepAliveHeld = false;
        await _keepAlive.end();
      }
    }
    if (!_disposed) notifyListeners();
  }

  /// Loads the on-device source classifier (FR-09), or null where there is none.
  final Future<WindowClassifier> Function()? _loadClassifier;
  WindowClassifier? _classifier;
  bool _classifierTried = false;
  bool _classificationEnabled = true;

  /// Whether readings will carry a noise source.
  bool get classifierAvailable => _classifier != null;

  /// The Settings "Classify noise source" switch.
  bool get classificationEnabled => _classificationEnabled;

  void setClassificationEnabled(bool enabled) {
    if (enabled == _classificationEnabled) return;
    _classificationEnabled = enabled;
    _classifier?.enabled = enabled;
    // Partial totals from before the switch are discarded.
    _classifier?.reset();
    notifyListeners();
  }

  /// The source of the last completed window, for the Monitor screen.
  SourceClassification? get lastSource => _lastSource;
  SourceClassification? _lastSource;

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

  /// Windows measured but not stored.
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
      // Requested before capture opens and while the app is visible.
      _keepAliveHeld = _backgroundEnabled && await _keepAlive.begin();
      if (_disposed) {
        await _release();
        return;
      }
      await _ensureClassifier();
      final stream = await _source.start();
      if (_disposed) {
        await _source.stop();
        return;
      }
      _classifier?.reset();
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

  /// Stops measuring and releases the microphone.
  Future<void> stop() async {
    await _release();
    if (_disposed) return;
    _setStatus(MeasurementStatus.idle);
  }

  /// Called when the app leaves or returns to the foreground.
  Future<void> onForegroundChanged({required bool inForeground}) async {
    if (!inForeground && isMeasuring && !_keepAliveHeld) await stop();
  }

  void _onSamples(Int16List samples) {
    final meter = _meter;
    if (meter == null) return;
    final out = meter.process(samples);
    _classifier?.add(samples);
    if (out.liveLevelsDb.isNotEmpty) _liveLevelDb = out.liveLevelsDb.last;
    _elapsed = meter.elapsedInWindow;
    for (final w in out.windows) {
      _lastWindow = w;
      // Taken synchronously as the window closes, so the next window's frames start a fresh tally.
      final source = _classifier?.takeWindow();
      if (source != null) {
        _lastSource = source;
        // Debug builds only; stripped from release.
        if (kDebugMode) {
          debugPrint(
            'NS-CLASSIFY ${w.start.toIso8601String()} '
            'laeq=${w.laeqDb.toStringAsFixed(1)} -> ${source.label} '
            '${source.confidence?.toStringAsFixed(2) ?? '-'} | '
            'frames=${source.framesClassified} dropped=${source.framesDropped} '
            'infer=${source.meanInference.inMilliseconds}ms | top: '
            '${source.topLabels.map((t) => '${t.$1}=${t.$2.toStringAsFixed(2)}').join(', ')}',
          );
        }
      } else if (kDebugMode) {
        // Diagnostic for a window saved without a source.
        debugPrint(
          'NS-CLASSIFY ${w.start.toIso8601String()} -> none | '
          'loaded=${_classifier != null} tried=$_classifierTried '
          'enabled=$_classificationEnabled '
          'droppedTotal=${_classifier?.framesDropped ?? '-'}',
        );
      }
      _submit(w, source);
    }
    if (out.liveLevelsDb.isNotEmpty || out.windows.isNotEmpty) {
      notifyListeners();
    }
  }

  Future<void> _ensureClassifier() async {
    final load = _loadClassifier;
    if (_classifierTried || load == null) return;
    _classifierTried = true;
    try {
      _classifier = await load()
        ..enabled = _classificationEnabled;
    } on Object catch (e, stack) {
      // Model missing or the runtime unavailable: measure without labels.
      if (kDebugMode) debugPrint('NS-CLASSIFY load failed: $e\n$stack');
      _classifier = null;
    }
  }

  Future<void> _submit(MeasuredWindow w, SourceClassification? source) async {
    // laeq carries the energy average used for dose.
    final confidence = source?.confidence;
    final reading = NoiseReading(
      timestamp: w.start,
      dbA: _round1(w.maxFastDb),
      laeq: _round1(w.laeqDb),
      classLabel: source?.label,
      // Two decimals; the UI shows a whole percentage.
      confidence: confidence == null
          ? null
          : (confidence * 100).roundToDouble() / 100,
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
    // Released after the microphone, so the notification never disappears while capture is still open.
    if (_keepAliveHeld) {
      _keepAliveHeld = false;
      await _keepAlive.end();
    }
  }

  void _setStatus(MeasurementStatus s) {
    _status = s;
    notifyListeners();
  }

  /// One decimal: the display precision.
  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stopRequests.cancel());
    // Fire and forget: the microphone must be released on sign-out.
    unawaited(_release());
    unawaited(_classifier?.close());
    super.dispose();
  }
}
