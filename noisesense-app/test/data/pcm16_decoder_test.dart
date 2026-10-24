import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/data/audio/pcm16_decoder.dart';

Uint8List _bytes(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('decodes little-endian signed samples, including the extremes', () {
    final samples = [0, 1, -1, 32767, -32768, 1234, -1234];
    expect(Pcm16Decoder().convert(_bytes(samples)), samples);
  });

  test('a sample split across two buffers is reassembled, not lost', () {
    // Dropping an odd byte would misalign every later sample.
    final samples = [1000, -2000, 3000, -4000];
    final all = _bytes(samples);
    final decoder = Pcm16Decoder();
    final first = decoder.convert(Uint8List.sublistView(all, 0, 3));
    final second = decoder.convert(Uint8List.sublistView(all, 3));
    expect([...first, ...second], samples);
  });

  test('output is identical for every way of splitting the stream', () {
    final samples = List<int>.generate(50, (i) => (i * 1311) % 65536 - 32768);
    final all = _bytes(samples);
    for (var split = 1; split < all.length; split++) {
      final decoder = Pcm16Decoder();
      final out = [
        ...decoder.convert(Uint8List.sublistView(all, 0, split)),
        ...decoder.convert(Uint8List.sublistView(all, split)),
      ];
      expect(out, samples, reason: 'split at byte $split');
    }
  });

  test('one-byte buffers still decode correctly', () {
    final samples = [-5, 7, -32768];
    final decoder = Pcm16Decoder();
    final out = <int>[];
    for (final b in _bytes(samples)) {
      out.addAll(decoder.convert(Uint8List.fromList([b])));
    }
    expect(out, samples);
  });

  test('an empty buffer keeps a pending byte rather than dropping it', () {
    final all = _bytes([4321]);
    final decoder = Pcm16Decoder();
    expect(decoder.convert(Uint8List.sublistView(all, 0, 1)), isEmpty);
    expect(decoder.convert(Uint8List(0)), isEmpty);
    expect(decoder.convert(Uint8List.sublistView(all, 1)), [4321]);
  });

  test('reset discards a pending byte from a previous capture', () {
    final decoder = Pcm16Decoder();
    decoder.convert(Uint8List.fromList([0xFF]));
    decoder.reset();
    expect(decoder.convert(_bytes([10])), [10]);
  });
}
