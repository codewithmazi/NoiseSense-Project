import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/data/ml/yamnet_model.dart';
import 'package:noise_sense/domain/acoustics/source_classifier.dart';

void main() {
  test('LF and CRLF label files parse to the same labels', () {
    expect(YamnetModel.parseLabels('Speech\nVehicle\n'), ['Speech', 'Vehicle']);
    expect(YamnetModel.parseLabels('Speech\r\nVehicle\r\n'), [
      'Speech',
      'Vehicle',
    ]);
  });

  test('the bundled labels load the shipped category map', () {
    // Regression (22 Oct): CRLF line endings stopped classification.
    final labels = YamnetModel.parseLabels(
      File('assets/models/yamnet_labels.txt').readAsStringSync(),
    );
    expect(labels, hasLength(521));
    expect(
      () => SourceCategoryMap.parse(
        File('assets/models/source_categories.json').readAsStringSync(),
        labels,
      ),
      returnsNormally,
    );
  });
}
