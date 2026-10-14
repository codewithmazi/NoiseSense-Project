import '../models/exposure_settings.dart';
import '../models/noise_reading.dart';

/// Result of submitting a reading.
enum SubmitOutcome {
  /// The service stored the reading for the first time.
  stored,

  /// The service already held this reading and ignored the repeat. This is the
  /// expected outcome when the offline outbox replays a reading whose first
  /// acknowledgement was lost, so it counts as success (603: FR-06).
  duplicate,
}

/// Everything the app needs from wherever readings and settings are kept.
///
/// This interface belongs to the domain layer and names no provider, protocol
/// or storage technology. The AWS-specific implementation lives in the data
/// layer and is supplied from outside. Changing cloud provider therefore means
/// writing one new implementation, not editing screens or business rules
/// (603: NFR-06; lock-in mitigation after Opara-Martins et al., 2016).
abstract interface class NoiseRepository {
  /// The user's recent readings, newest first.
  Future<List<NoiseReading>> history();

  /// Sends one reading. Safe to call again with the same reading.
  Future<SubmitOutcome> submit(NoiseReading reading);

  /// The user's current exposure settings.
  Future<ExposureSettings> settings();

  /// Changes the alert threshold and returns the settings now in force.
  Future<ExposureSettings> updateThreshold(double thresholdDbA);
}
