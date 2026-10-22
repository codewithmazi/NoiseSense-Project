import '../models/noise_reading.dart';

/// Where an outbox entry stands.
enum OutboxState {
  /// Waiting to upload or retry.
  pending,

  /// Rejected as invalid; kept but never retried.
  rejected,
}

/// One reading held on the device until the service acknowledges it.
class OutboxEntry {
  const OutboxEntry({
    required this.reading,
    required this.state,
    required this.attempts,
    this.lastError,
  });

  final NoiseReading reading;
  final OutboxState state;

  /// Upload attempts that have failed so far.
  final int attempts;

  final String? lastError;
}

/// Durable storage for readings not yet stored by the service.
abstract interface class OutboxStore {
  /// Adds a reading; duplicates by timestamp are ignored.
  Future<void> add(NoiseReading reading);

  /// Pending entries, oldest first.
  Future<List<OutboxEntry>> pending({int limit = 50});

  /// all entries, oldest first.
  Future<List<OutboxEntry>> all();

  /// Removes an entry once stored by the service.
  Future<void> remove(DateTime timestamp);

  /// Records a failed attempt that is worth retrying.
  Future<void> recordFailure(DateTime timestamp, String error);

  /// Marks an entry as rejected.
  Future<void> reject(DateTime timestamp, String error);

  /// Releases the underlying storage.
  Future<void> close();
}
