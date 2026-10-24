import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/acoustics/source_classifier.dart';

/// The real bundled files, read from disk.
final _labels = File('assets/models/yamnet_labels.txt')
    .readAsLinesSync()
    .where((l) => l.isNotEmpty)
    .toList();
final _mappingJson = File('assets/models/source_categories.json')
    .readAsStringSync();

/// A model whose scores are scripted per call.
class _FakeModel implements ScoreModel {
  _FakeModel(this.labels);

  @override
  final List<String> labels;
  @override
  int get frameLength => 160; // tiny frames keep the tests fast

  final queue = <Map<String, double>>[];
  Completer<void>? gate;
  int calls = 0;
  bool throwNext = false;
  bool closed = false;

  @override
  Future<Float32List> score(Float32List frame) async {
    calls++;
    await gate?.future;
    if (throwNext) {
      throwNext = false;
      throw Exception('inference failed');
    }
    final out = Float32List(labels.length);
    final scripted = queue.isEmpty ? <String, double>{} : queue.removeAt(0);
    scripted.forEach((label, s) => out[labels.indexOf(label)] = s);
    return out;
  }

  @override
  Future<void> close() async => closed = true;
}

/// Enough 48 kHz samples to complete [frames] model frames of 160 at 16 kHz.
Int16List _audio(int frames) => Int16List(frames * 160 * 3);

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('the shipped mapping', () {
    test('every listed name is a real YAMNet label', () {
      // Throws on a misspelling, which would otherwise silently weaken a category by matching nothing.
      final map = SourceCategoryMap.parse(_mappingJson, _labels);
      expect(map.categoryNames, ['road_traffic', 'speech', 'construction']);
    });

    test('the label list is the 521 YAMNet classes', () {
      expect(_labels, hasLength(521));
      expect(_labels.first, 'Speech');
    });

    test('no label is assigned to two categories', () {
      final cats = (jsonDecode(_mappingJson)['categories'] as Map).values
          .expand((v) => (v as List).cast<String>())
          .toList();
      expect(cats.toSet().length, cats.length);
    });

    test('an unknown label is rejected, not ignored', () {
      const bad = '{"min_score":0.2,"categories":{"speech":["Speach"]}}';
      expect(
        () => SourceCategoryMap.parse(bad, _labels),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('category scores', () {
    final map = SourceCategoryMap.parse(_mappingJson, _labels);
    Float32List scores(Map<String, double> s) {
      final out = Float32List(_labels.length);
      s.forEach((l, v) => out[_labels.indexOf(l)] = v);
      return out;
    }

    test('a category scores its best member, not the sum of members', () {
      // Three overlapping traffic labels at 0.4 must not outweigh one clear speech label at 0.6.
      final c = map.categoryScores(
        scores({
          'Car': 0.4,
          'Vehicle': 0.4,
          'Car passing by': 0.4,
          'Speech': 0.6,
        }),
      );
      expect(c['road_traffic'], closeTo(0.4, 1e-6));
      expect(c['speech'], closeTo(0.6, 1e-6));
    });

    test('labels outside every category count for none', () {
      final c = map.categoryScores(scores({'Music': 0.9}));
      expect(c.values.every((v) => v == 0), isTrue);
    });
  });

  group('window classification', () {
    late _FakeModel model;
    late WindowClassifier wc;

    setUp(() {
      model = _FakeModel(_labels);
      wc = WindowClassifier(
        model: model,
        categories: SourceCategoryMap.parse(_mappingJson, _labels),
      );
    });

    test('the window takes the category with the highest mean score', () async {
      model.queue.addAll([
        {'Car': 0.9},
        {'Speech': 0.5},
        {'Car': 0.7},
      ]);
      for (var i = 0; i < 3; i++) {
        wc.add(_audio(1));
        await _settle();
      }
      final r = wc.takeWindow()!;
      expect(r.label, 'road_traffic');
      // (0.9 + 0 + 0.7) / 3
      expect(r.confidence, closeTo(0.533, 0.001));
      expect(r.framesClassified, 3);
    });

    test(
      'below the minimum score the window is "other", with no score',
      () async {
        model.queue.add({'Car': 0.1});
        wc.add(_audio(1));
        await _settle();
        final r = wc.takeWindow()!;
        expect(r.label, 'other');
        expect(r.confidence, isNull);
      },
    );

    test('a window with nothing classified has no source at all', () {
      // No guess is better than a fabricated one.
      expect(wc.takeWindow(), isNull);
    });

    test('each window starts a fresh tally', () async {
      model.queue.addAll([
        {'Car': 0.9},
        {'Speech': 0.8},
      ]);
      wc.add(_audio(1));
      await _settle();
      wc.takeWindow();
      wc.add(_audio(1));
      await _settle();
      expect(wc.takeWindow()!.label, 'speech');
    });

    test(
      'a frame arriving while the model is busy is dropped and counted',
      () async {
        // Bounded memory: audio is never queued behind a slow model.
        model.gate = Completer<void>();
        wc.add(_audio(3));
        expect(model.calls, 1);
        expect(wc.framesDropped, 2);
        model.gate!.complete();
        await _settle();
      },
    );

    test('a failed inference loses that frame, not the window', () async {
      model.throwNext = true;
      model.queue.add({'Speech': 0.9});
      wc.add(_audio(1));
      await _settle();
      wc.add(_audio(1));
      await _settle();
      expect(wc.takeWindow()!.label, 'speech');
      expect(wc.framesDropped, 1);
    });

    test('when disabled, nothing reaches the model', () {
      wc.enabled = false;
      wc.add(_audio(5));
      expect(model.calls, 0);
      expect(wc.takeWindow(), isNull);
    });
  });
}
