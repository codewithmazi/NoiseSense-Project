import '../../domain/models/noise_reading.dart';
import '../../domain/repositories/outbox_store.dart';

/// An [OutboxStore] opened on first use.
///
/// The real store is per user, so it cannot be opened until the user's ID is
/// known, and finding that out is asynchronous. The dashboard, though, is
/// built synchronously at sign-in. This wrapper lets it be handed a store at
/// once while the database opens behind it; every call waits for the same
/// single open.
class DeferredOutboxStore implements OutboxStore {
  DeferredOutboxStore(Future<OutboxStore> Function() open) : _open = open;

  final Future<OutboxStore> Function() _open;
  Future<OutboxStore>? _store;

  Future<OutboxStore> get _ready => _store ??= _open();

  @override
  Future<void> add(NoiseReading reading) async => (await _ready).add(reading);

  @override
  Future<List<OutboxEntry>> pending({int limit = 50}) async =>
      (await _ready).pending(limit: limit);

  @override
  Future<List<OutboxEntry>> all() async => (await _ready).all();

  @override
  Future<void> remove(DateTime timestamp) async =>
      (await _ready).remove(timestamp);

  @override
  Future<void> recordFailure(DateTime timestamp, String error) async =>
      (await _ready).recordFailure(timestamp, error);

  @override
  Future<void> reject(DateTime timestamp, String error) async =>
      (await _ready).reject(timestamp, error);

  /// Closes the store only if it was ever opened, so signing out quickly
  /// does not open a database just to close it.
  @override
  Future<void> close() async {
    final store = _store;
    if (store != null) await (await store).close();
  }
}
