import 'dart:typed_data';

/// Reassembles little-endian 16-bit samples from a byte stream.
class Pcm16Decoder {
  int? _carry;

  Int16List convert(Uint8List bytes) {
    final carry = _carry;
    final total = bytes.length + (carry == null ? 0 : 1);
    final samples = Int16List(total ~/ 2);

    var byteIndex = 0;
    var sampleIndex = 0;
    if (carry != null && bytes.isNotEmpty) {
      samples[sampleIndex++] = _sample(carry, bytes[0]);
      byteIndex = 1;
    }
    for (; byteIndex + 1 < bytes.length; byteIndex += 2) {
      samples[sampleIndex++] = _sample(bytes[byteIndex], bytes[byteIndex + 1]);
    }

    if (carry != null && bytes.isEmpty) {
      _carry = carry; // Nothing arrived to complete it; keep waiting.
    } else {
      _carry = byteIndex < bytes.length ? bytes[byteIndex] : null;
    }
    return samples;
  }

  void reset() => _carry = null;

  static int _sample(int low, int high) {
    final value = low | (high << 8);
    return value >= 0x8000 ? value - 0x10000 : value;
  }
}
