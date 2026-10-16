import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/data/local/sqlite_outbox_store.dart';
import 'package:noise_sense/domain/models/noise_reading.dart';
import 'package:noise_sense/domain/repositories/outbox_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs the store against a real SQLite database, through FFI, so the SQL,
/// the schema and the persistence behaviour are what is tested, not a fake.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('outbox_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<SqliteOutboxStore> open([String owner = 'user-a']) =>
      SqliteOutboxStore.open(
        ownerId: owner,
        factory: factory,
        directory: dir.path,
      );

  NoiseReading reading(int minute, {double dbA = 60}) => NoiseReading(
    timestamp: DateTime.utc(2026, 10, 16, 9, minute),
    dbA: dbA,
    laeq: dbA - 1,
    classLabel: 'road_traffic',
    confidence: 0.72,
  );

  test('a reading survives a round trip with every field intact', () async {
    final store = await open();
    final r = reading(1);
    await store.add(r);
    final back = (await store.all()).single;
    expect(back.reading, r);
    expect(back.state, OutboxState.pending);
    expect(back.attempts, 0);
    await store.close();
  });

  test('readings persist after the database is closed and reopened', () async {
    // The guarantee the outbox exists for: the process can die and nothing
    // queued is lost.
    final first = await open();
    await first.add(reading(1));
    await first.add(reading(2));
    await first.close();

    final second = await open();
    expect((await second.all()).map((e) => e.reading.timestamp), [
      reading(1).timestamp,
      reading(2).timestamp,
    ]);
    await second.close();
  });

  test('adding the same reading twice keeps one entry, untouched', () async {
    final store = await open();
    await store.add(reading(1));
    await store.recordFailure(reading(1).timestamp, 'offline');
    await store.add(reading(1, dbA: 99));
    final entries = await store.all();
    expect(entries, hasLength(1));
    // The repeat did not reset the attempt count or overwrite the values.
    expect(entries.single.attempts, 1);
    expect(entries.single.reading.dbA, 60);
    await store.close();
  });

  test('pending is oldest first and respects the limit', () async {
    final store = await open();
    for (final m in [5, 1, 3, 2, 4]) {
      await store.add(reading(m));
    }
    final batch = await store.pending(limit: 3);
    expect(batch.map((e) => e.reading.timestamp.minute), [1, 2, 3]);
    await store.close();
  });

  test('a rejected entry leaves pending but stays in the store', () async {
    final store = await open();
    await store.add(reading(1));
    await store.add(reading(2));
    await store.reject(reading(1).timestamp, 'invalid');
    expect((await store.pending()).single.reading.timestamp.minute, 2);
    final rejected = (await store.all()).firstWhere(
      (e) => e.state == OutboxState.rejected,
    );
    expect(rejected.lastError, 'invalid');
    expect(rejected.attempts, 1);
    await store.close();
  });

  test('remove deletes only the acknowledged entry', () async {
    final store = await open();
    await store.add(reading(1));
    await store.add(reading(2));
    await store.remove(reading(1).timestamp);
    expect((await store.all()).single.reading.timestamp.minute, 2);
    await store.close();
  });

  test('each user has a separate outbox', () async {
    // Readings queued by one account must never be uploaded under another
    // account that signs in on the same phone.
    final a = await open('user-a');
    await a.add(reading(1));
    await a.close();

    final b = await open('user-b');
    expect(await b.all(), isEmpty);
    await b.close();

    final aAgain = await open('user-a');
    expect(await aAgain.all(), hasLength(1));
    await aAgain.close();
  });

  test('an owner id cannot escape the database directory', () async {
    // The file name is built from the id, so path characters are replaced.
    final store = await open('../../evil');
    await store.add(reading(1));
    await store.close();
    final files = dir.listSync().map((f) => f.uri.pathSegments.last).toList();
    expect(files, contains('outbox_______evil.db'));
  });

  test('the schema rejects an unknown state', () async {
    final store = await open();
    await store.close();
    final raw = await factory.openDatabase(
      '${dir.path}${Platform.pathSeparator}outbox_user-a.db',
    );
    await expectLater(
      raw.insert('outbox', {
        'ts': 1,
        'db_a': 60.0,
        'state': 'lost',
        'queued_at': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await raw.close();
  });
}
