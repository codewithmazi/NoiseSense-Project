import 'dart:typed_data';

/// A live stream of mono 16-bit audio samples.
abstract interface class PcmSource {
  /// Sample rate of the stream returned by [start].
  int get sampleRate;

  /// Requests microphone permission; returns whether capture is allowed.
  Future<bool> ensurePermission();

  /// Starts capture and returns ordered sample chunks.
  Future<Stream<Int16List>> start();

  /// Stops capture and releases the microphone.
  Future<void> stop();
}
