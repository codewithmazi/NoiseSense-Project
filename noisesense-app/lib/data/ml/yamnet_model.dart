import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../domain/acoustics/source_classifier.dart';

/// YAMNet through TensorFlow Lite (LiteRT), run on a background isolate.
///
/// [IsolateInterpreter] keeps inference off the UI thread, so a slow frame on
/// an older phone delays the next classification rather than a screen
/// redraw. The model and label list are bundled assets, so classification
/// needs no network, which is what makes it "on-device" and keeps working
/// with the outbox offline.
class YamnetModel implements ScoreModel {
  YamnetModel._(this._interpreter, this._isolate, this.labels);

  static const modelAsset = 'assets/models/yamnet.tflite';
  static const labelsAsset = 'assets/models/yamnet_labels.txt';

  static Future<YamnetModel> load() async {
    final interpreter = await Interpreter.fromAsset(modelAsset);
    final isolate = await IsolateInterpreter.create(
      address: interpreter.address,
    );
    final labels = (await rootBundle.loadString(labelsAsset))
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();
    return YamnetModel._(interpreter, isolate, labels);
  }

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  @override
  final List<String> labels;

  @override
  int get frameLength => 15600;

  @override
  Future<Float32List> score(Float32List frame) async {
    final output = [List<double>.filled(labels.length, 0)];
    await _isolate.run(frame, output);
    return Float32List.fromList(output[0]);
  }

  @override
  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}
