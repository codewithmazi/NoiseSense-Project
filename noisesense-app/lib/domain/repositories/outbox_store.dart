import '../models/noise_reading.dart';

/// Where an outbox entry stands.
enum OutboxState {
  /// Waiting to be uploaded, or to be retried after a failure that may pass.
  pending,

  /// Refused by the service as invalid. Kept, not deleted, and not retried:
  /// sending the same request again would only be refused again. This is the
  /// device-side counterpart of the backend's dead-letter queue.
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
///
/// Entries are keyed by the reading's timestamp, which is also the key the
/// backend uses to recognise a repeat. Using the same key at both ends is what
/// makes delivery effectively once: the device may send a reading more than
/// once, and the service stores it once.
abstract interface class OutboxStore {
  /// Adds a reading. Adding one whose timestamp is already held is ignored,
  /// so a reading can never be queued twice.
  Future<void> add(NoiseReading reading);

  /// Pending entries, oldest first.
  Future<List<OutboxEntry>> pending({int limit = 50});

  /// Every entry, pending and rejected, oldest first.
  Future<List<OutboxEntry>> all();

  /// Deletes an entry once the service holds the reading.
  Future<void> remove(DateTime timestamp);

  /// Records a failed attempt that is worth retrying.
  Future<void> recordFailure(DateTime timestamp, String error);

  /// Sets an entry aside as refused by the service.
  Future<void> reject(DateTime timestamp, String error);

  /// Releases the underlying storage.
  Future<void> close();
}
