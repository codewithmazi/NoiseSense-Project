import 'package:noise_sense/domain/models/noise_reading.dart';
import 'package:noise_sense/domain/repositories/outbox_store.dart';

/// In-memory [OutboxStore] for tests of code that uses the outbox.
class MemoryOutboxStore implements OutboxStore {
  final Map<DateTime, OutboxEntry> _entries = {};

  /// When set, [add] throws it, to simulate a full or broken disk.
  Exception? addError;
  bool closed = false;

  @override
  Future<void> add(NoiseReading reading) async {
    final error = addError;
    if (error != null) throw error;
    _entries.putIfAbsent(
      reading.timestamp,
      () => OutboxEntry(
        reading: reading,
        state: OutboxState.pending,
        attempts: 0,
      ),
    );
  }

  List<OutboxEntry> _sorted() =>
      _entries.values.toList()
        ..sort((a, b) => a.reading.timestamp.compareTo(b.reading.timestamp));

  @override
  Future<List<OutboxEntry>> pending({int limit = 50}) async => _sorted()
      .where((e) => e.state == OutboxState.pending)
      .take(limit)
      .toList();

  @override
  Future<List<OutboxEntry>> all() async => _sorted();

  @override
  Future<void> remove(DateTime timestamp) async => _entries.remove(timestamp);

  @override
  Future<void> recordFailure(DateTime timestamp, String error) async =>
      _update(timestamp, OutboxState.pending, error);

  @override
  Future<void> reject(DateTime timestamp, String error) async =>
      _update(timestamp, OutboxState.rejected, error);

  void _update(DateTime ts, OutboxState state, String error) {
    final e = _entries[ts];
    if (e == null) return;
    _entries[ts] = OutboxEntry(
      reading: e.reading,
      state: state,
      attempts: e.attempts + 1,
      lastError: error,
    );
  }

  OutboxEntry? entryAt(DateTime ts) => _entries[ts];

  @override
  Future<void> close() async => closed = true;
}

/// Lets queued microtasks and zero-delay timers run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
