import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'decimator.dart';

/// A pre-trained audio model: one frame of 16 kHz audio in, one score per
/// label out.
///
/// The domain sees only this interface. The TensorFlow Lite implementation
/// lives in the data layer, and tests supply scripted scores, so the logic
/// that turns scores into a reading's source is tested without the model.
abstract interface class ScoreModel {
  /// Samples per frame (YAMNet: 15,600, i.e. 0.975 s at 16 kHz).
  int get frameLength;

  /// Label names, indexed as the scores are.
  List<String> get labels;

  /// Scores for one frame. YAMNet's are independent sigmoid outputs in 0–1,
  /// not a probability distribution: they need not sum to one.
  Future<Float32List> score(Float32List frame);

  Future<void> close();
}

/// The dominant noise source in one measurement window.
class SourceClassification {
  const SourceClassification({
    required this.label,
    required this.confidence,
    required this.framesClassified,
    this.framesDropped = 0,
    this.topLabels = const [],
    this.meanInference = Duration.zero,
  });

  /// Frames lost this window because the model was still busy or failed.
  final int framesDropped;

  /// The model's five highest mean label scores for the window, for
  /// diagnosis: label names and numbers only, never audio. Added after the
  /// first on-device test labelled every window "other", to show what the
  /// model actually heard.
  final List<(String, double)> topLabels;

  /// Mean time per inference this window, which experiment M8 also needs.
  final Duration meanInference;

  /// One of [SourceCategoryMap.categoryNames], or `other`.
  final String label;

  /// Mean model score for [label] across the window's frames, or null for
  /// `other`. A model score, not a calibrated probability; experiment M7
  /// measures how far it can be trusted.
  final double? confidence;

  final int framesClassified;
}

/// Which model labels count towards which NoiseSense source category.
///
/// Read from `assets/models/source_categories.json`. The M7 evaluation
/// script reads the same file, so the mapping that is evaluated is exactly
/// the mapping that ships.
class SourceCategoryMap {
  SourceCategoryMap._(
    this.categoryNames,
    this._labelsByCategory,
    this.minScore,
  );

  /// Parses the mapping and resolves every name to a model label index.
  ///
  /// Throws [FormatException] if a name is not one of [modelLabels]. A
  /// misspelt label would otherwise match nothing and silently weaken its
  /// category.
  factory SourceCategoryMap.parse(String json, List<String> modelLabels) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final index = {
      for (var i = 0; i < modelLabels.length; i++) modelLabels[i]: i,
    };
    final categories = root['categories'] as Map<String, dynamic>;
    final resolved = <String, List<int>>{};
    for (final MapEntry(key: name, value: members) in categories.entries) {
      resolved[name] = [
        for (final label in (members as List).cast<String>())
          index[label] ??
              (throw FormatException(
                'Category "$name" lists "$label", which is not a model label',
              )),
      ];
    }
    return SourceCategoryMap._(
      resolved.keys.toList(),
      resolved,
      (root['min_score'] as num).toDouble(),
    );
  }

  final List<String> categoryNames;
  final Map<String, List<int>> _labelsByCategory;

  /// Below this mean score, no category is claimed and the window is
  /// reported as `other`.
  final double minScore;

  /// One score per category for one frame: the highest score among its
  /// member labels.
  ///
  /// The maximum rather than the sum, because YAMNet's labels overlap
  /// ("Vehicle", "Car", "Car passing by" all fire for one car). Summing would
  /// reward categories for having many near-synonymous labels, not for being
  /// more likely.
  Map<String, double> categoryScores(Float32List scores) => {
    for (final MapEntry(key: name, value: idx) in _labelsByCategory.entries)
      name: idx.fold(0.0, (best, i) => scores[i] > best ? scores[i] : best),
  };
}

/// Classifies the audio of each measurement window.
///
/// ## What is kept
///
/// The model needs one frame of audio at a time, so this class holds up to
/// 0.975 s of 16 kHz samples in memory, overwritten as each frame is passed
/// to the model. Nothing else is retained: per-category score totals
/// accumulate, and the audio does not. No frame is written to storage or
/// sent off the device. This qualifies, rather than breaks, the privacy
/// design: the level meter keeps no audio at all, and the classifier keeps
/// under a second of it transiently.
///
/// ## Keeping up
///
/// Inference runs asynchronously. If a frame is ready while the previous one
/// is still being scored, the new frame is dropped and counted rather than
/// queued: a queue would grow without bound on a phone that cannot keep up,
/// and a backlog of audio is exactly what the privacy design avoids holding.
/// [framesDropped] makes that visible for experiment M8.
class WindowClassifier {
  WindowClassifier({required this.model, required this.categories})
    : _frame = Float32List(model.frameLength);

  final ScoreModel model;
  final SourceCategoryMap categories;
  final Decimator _decimator = Decimator();
  final Float32List _frame;
  int _filled = 0;
  bool _busy = false;

  final Map<String, double> _totals = {};
  Float64List? _labelTotals;
  int _windowDropped = 0;
  int _inferenceMicros = 0;
  int _frames = 0;
  int _dropped = 0;
  bool enabled = true;

  int get framesDropped => _dropped;

  /// Feeds 48 kHz samples. Returns immediately; scoring happens behind it.
  void add(Int16List samples) {
    if (!enabled) return;
    final scaled = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      scaled[i] = samples[i] / 32768.0;
    }
    final down = _decimator.process(scaled);
    var i = 0;
    while (i < down.length) {
      final take = (_frame.length - _filled).clamp(0, down.length - i);
      _frame.setRange(_filled, _filled + take, down, i);
      _filled += take;
      i += take;
      if (_filled == _frame.length) {
        _filled = 0;
        if (_busy) {
          _dropped++;
          _windowDropped++;
        } else {
          unawaited(_score(Float32List.fromList(_frame)));
        }
      }
    }
  }

  Future<void> _score(Float32List frame) async {
    _busy = true;
    final timer = Stopwatch()..start();
    try {
      final scores = await model.score(frame);
      _inferenceMicros += timer.elapsedMicroseconds;
      categories.categoryScores(scores).forEach((name, s) {
        _totals[name] = (_totals[name] ?? 0) + s;
      });
      final totals = _labelTotals ??= Float64List(scores.length);
      for (var i = 0; i < scores.length; i++) {
        totals[i] += scores[i];
      }
      _frames++;
    } on Exception {
      // A failed inference loses one frame's opinion, not the measurement.
      _dropped++;
      _windowDropped++;
    } finally {
      // The copy handed to the model is released here; nothing keeps it.
      _busy = false;
    }
  }

  /// The source for the window just completed, and a fresh start for the
  /// next. Null when nothing was classified (disabled, or every frame
  /// dropped), so the reading carries no source rather than a guess.
  ///
  /// A frame still being scored when the window closes counts towards the
  /// next window: at most 0.975 s of one window's audio is attributed to
  /// its neighbour.
  SourceClassification? takeWindow() {
    if (_frames == 0) {
      _reset();
      return null;
    }
    var best = '';
    var bestMean = -1.0;
    _totals.forEach((name, total) {
      final mean = total / _frames;
      if (mean > bestMean) {
        best = name;
        bestMean = mean;
      }
    });
    final labelTotals = _labelTotals;
    final top = <(String, double)>[];
    if (labelTotals != null) {
      final order = List<int>.generate(labelTotals.length, (i) => i)
        ..sort((a, b) => labelTotals[b].compareTo(labelTotals[a]));
      for (final i in order.take(5)) {
        top.add((model.labels[i], labelTotals[i] / _frames));
      }
    }
    final claimed = bestMean >= categories.minScore;
    final result = SourceClassification(
      label: claimed ? best : 'other',
      confidence: claimed ? bestMean : null,
      framesClassified: _frames,
      framesDropped: _windowDropped,
      topLabels: top,
      meanInference: Duration(microseconds: _inferenceMicros ~/ _frames),
    );
    _reset();
    return result;
  }

  void _reset() {
    _totals.clear();
    _labelTotals?.fillRange(0, _labelTotals!.length, 0);
    _windowDropped = 0;
    _inferenceMicros = 0;
    _frames = 0;
  }

  /// Clears audio and totals, for example when measurement stops.
  void reset() {
    _reset();
    _decimator.reset();
    _filled = 0;
    _frame.fillRange(0, _frame.length, 0);
  }

  Future<void> close() => model.close();
}
