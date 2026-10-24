import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/noise_reading.dart';
import '../../domain/repositories/outbox_store.dart';

/// [OutboxStore] in a SQLite database on the device.
class SqliteOutboxStore implements OutboxStore {
  SqliteOutboxStore._(this._db);

  /// Opens (creating if needed) the outbox for [ownerId].
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

  // Schema: `ts` (UTC ms) is the primary key, the same identity the backend uses.
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
    // A repeat leaves the queued reading and its attempt count unchanged.
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

  /// Sanitised, because the file name is built from the user ID.
  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
