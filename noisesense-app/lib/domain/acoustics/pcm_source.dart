import 'dart:typed_data';

/// A live stream of mono 16-bit audio samples.
///
/// Part of the domain because the measurement logic depends on it, but it names
/// no plugin and no platform. The microphone implementation lives in the data
/// layer; tests supply generated tones through the same interface, which is how
/// the whole measurement path is exercised without a phone.
abstract interface class PcmSource {
  /// Samples per second of the stream [start] returns.
  int get sampleRate;

  /// Asks for microphone access if it has not been granted. Returns whether
  /// capture is now allowed.
  Future<bool> ensurePermission();

  /// Starts capture. Each event is the next run of samples, in order.
  Future<Stream<Int16List>> start();

  /// Stops capture and releases the microphone. Safe to call when stopped.
  Future<void> stop();
}
