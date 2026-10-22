import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/core/database/app_database.dart';

void main() {
  late AppDatabase database;
  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test(
    'opens initial schema with foreign keys and durable reading tables',
    () async {
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 1);
      final foreignKeys = await database
          .customSelect('PRAGMA foreign_keys')
          .getSingle();
      expect(foreignKeys.read<int>('foreign_keys'), 1);
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      expect(tables.map((row) => row.read<String>('name')).toSet(), {
        'reading_progress_entries',
        'library_entries',
        'chapter_bookmark_entries',
      });
    },
  );

  test('transactions roll back when an operation fails', () async {
    // This temporary table only exists inside the test database.
    await database.customStatement(
      'CREATE TEMP TABLE probe (id INTEGER PRIMARY KEY)',
    );
    await expectLater(
      database.transaction(() async {
        await database.customStatement('INSERT INTO probe VALUES (1)');
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    final rows = await database.customSelect('SELECT * FROM probe').get();
    expect(rows, isEmpty);
  });
}
