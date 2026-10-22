import '../models/exposure_settings.dart';
import '../models/noise_reading.dart';

/// Result of submitting a reading.
enum SubmitOutcome {
  /// The service stored the reading for the first time.
  stored,

  /// the
  duplicate,
}


abstract interface class NoiseRepository {
  /// The user's recent readings, newest first.
  Future<List<NoiseReading>> history();

  /// Sends one reading. Safe to call again with the same reading.
  Future<SubmitOutcome> submit(NoiseReading reading);

  /// The user's current exposure settings.
  Future<ExposureSettings> settings();

  /// Changes the alert threshold and returns the settings now in action.
  Future<ExposureSettings> updateThreshold(double thresholdDbA);
}
