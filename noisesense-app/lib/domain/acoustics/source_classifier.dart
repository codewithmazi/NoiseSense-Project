import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'decimator.dart';

/// A pre-trained audio model: one 16 kHz audio frame in, one score per label out.
abstract interface class ScoreModel {
  /// Samples per frame.
  int get frameLength;

  /// Label names, indexed as the scores are.
  List<String> get labels;

  /// Scores for one frame; independent sigmoid outputs in 0–1.
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

  /// Frames dropped because the model was busy or failed.
  final int framesDropped;

  /// Five highest mean label scores, for diagnosis.
  final List<(String, double)> topLabels;

  /// Mean inference time per frame.
  final Duration meanInference;

  /// Source category, or `other`.
  final String label;

  /// Mean model score for [label], or null for `other`.
  final double? confidence;

  final int framesClassified;
}

/// Maps model labels to NoiseSense source categories.
class SourceCategoryMap {
  SourceCategoryMap._(
    this.categoryNames,
    this._labelsByCategory,
    this.minScore,
  );

  /// Parses the mapping and resolves label names to model indices.
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

  /// Minimum mean score required to claim a category.
  final double minScore;

  /// One score per category: the highest score among its member labels.
  Map<String, double> categoryScores(Float32List scores) => {
    for (final MapEntry(key: name, value: idx) in _labelsByCategory.entries)
      name: idx.fold(0.0, (best, i) => scores[i] > best ? scores[i] : best),
  };
}

/// Classifies the audio of each measurement window.
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

  /// Feeds 48 kHz samples; scoring happens asynchronously.
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
      // A failed inference drops one frame.
      _dropped++;
      _windowDropped++;
    } finally {
      _busy = false;
    }
  }

  /// Returns the source for the completed window, or null if none was classified.
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

  /// Clears audio and totals.
  void reset() {
    _reset();
    _decimator.reset();
    _filled = 0;
    _frame.fillRange(0, _frame.length, 0);
  }

  Future<void> close() => model.close();
}
