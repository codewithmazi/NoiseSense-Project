import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/noise_reading.dart';
import '../../domain/repositories/outbox_store.dart';

/// [OutboxStore] in a SQLite database on the device.
///
/// SQLite rather than a key-value store because the outbox needs exactly what
/// it provides: atomic writes that survive the process being killed
/// mid-write, a uniqueness constraint that makes [add] idempotent at the
/// storage layer, and ordered queries. A JSON file rewritten on every change
/// would need all three built by hand, and would lose the queue if the phone
/// died halfway through a write.
///
/// ## One database per user
///
/// The file is named after the signed-in user's Cognito subject. Without
/// that, readings queued by one account and still pending at sign-out would
/// be uploaded under the next account to sign in on the same phone: a
/// privacy failure, and corrupted data for both users. Separate files make
/// that impossible rather than merely unlikely, and keep a user's unsent
/// readings for when they sign back in.
class SqliteOutboxStore implements OutboxStore {
  SqliteOutboxStore._(this._db);

  /// Opens (creating if needed) the outbox for [ownerId].
  ///
  /// [factory] and [directory] exist for tests, which run against an
  /// in-memory database through FFI instead of the Android plugin.
  static Future<SqliteOutboxStore> open({
    required String ownerId,
    DatabaseFactory? factory,
    String? directory,
  }) async {
    final f = factory ?? databaseFactory;
    final dir = directory ?? await f.getDatabasesPath();
    final path = directory == inMemoryDatabasePath
        ? inMemoryDatabasePath
        : p.join(dir, 'outbox_${_safe(ownerId)}.db');
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _create),
    );
    return SqliteOutboxStore._(db);
  }

  final Database _db;

  // Schema. `ts` is the reading's timestamp in UTC milliseconds and the
  // primary key, the same identity the backend uses to detect a repeat.
  static Future<void> _create(Database db, int version) => db.execute('''
    CREATE TABLE outbox (
      ts          INTEGER PRIMARY KEY,
      db_a        REAL    NOT NULL,
      laeq        REAL,
      class_label TEXT,
      confidence  REAL,
      state       TEXT    NOT NULL DEFAULT 'pending'
                  CHECK (state IN ('pending', 'rejected')),
      attempts    INTEGER NOT NULL DEFAULT 0,
      last_error  TEXT,
      queued_at   INTEGER NOT NULL
    )
  ''');

  @override
  Future<void> add(NoiseReading r) => _db.insert('outbox', {
    'ts': r.timestamp.millisecondsSinceEpoch,
    'db_a': r.dbA,
    'laeq': r.laeq,
    'class_label': r.classLabel,
    'confidence': r.confidence,
    'queued_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    // A reading already queued is left exactly as it is, including its
    // attempt count, rather than being reset by the repeat.
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  @override
  Future<List<OutboxEntry>> pending({int limit = 50}) async => _map(
    await _db.query(
      'outbox',
      where: 'state = ?',
      whereArgs: ['pending'],
      orderBy: 'ts ASC',
      limit: limit,
    ),
  );

  @override
  Future<List<OutboxEntry>> all() async =>
      _map(await _db.query('outbox', orderBy: 'ts ASC'));

  @override
  Future<void> remove(DateTime timestamp) => _db.delete(
    'outbox',
    where: 'ts = ?',
    whereArgs: [timestamp.millisecondsSinceEpoch],
  );

  @override
  Future<void> recordFailure(DateTime timestamp, String error) => _db.rawUpdate(
    'UPDATE outbox SET attempts = attempts + 1, last_error = ? '
    'WHERE ts = ?',
    [error, timestamp.millisecondsSinceEpoch],
  );

  @override
  Future<void> reject(DateTime timestamp, String error) => _db.rawUpdate(
    "UPDATE outbox SET state = 'rejected', attempts = attempts + 1, "
    'last_error = ? WHERE ts = ?',
    [error, timestamp.millisecondsSinceEpoch],
  );

  @override
  Future<void> close() => _db.close();

  static List<OutboxEntry> _map(List<Map<String, Object?>> rows) => [
    for (final row in rows)
      OutboxEntry(
        reading: NoiseReading(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            row['ts']! as int,
            isUtc: true,
          ),
          dbA: (row['db_a']! as num).toDouble(),
          laeq: (row['laeq'] as num?)?.toDouble(),
          classLabel: row['class_label'] as String?,
          confidence: (row['confidence'] as num?)?.toDouble(),
        ),
        state: row['state'] == 'rejected'
            ? OutboxState.rejected
            : OutboxState.pending,
        attempts: row['attempts']! as int,
        lastError: row['last_error'] as String?,
      ),
  ];

  /// A Cognito sub is a UUID, but the file name is built from it, so anything
  /// outside a safe set is replaced rather than trusted.
  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
