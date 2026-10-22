import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/books/data/library_entries.dart';
import '../../features/reader/data/reading_progress_entries.dart';
import 'app_database.steps.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [ReadingProgressEntries, LibraryEntries])
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.open({required String name})
    : super(
        driftDatabase(
          name: name,
          native: DriftNativeOptions(
            databaseDirectory: getApplicationSupportDirectory,
          ),
        ),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: stepByStep(
      from1To2: (migrator, schema) async {
        await migrator.createTable(schema.readingProgressEntries);
        await migrator.createTable(schema.libraryEntries);
      },
    ),
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
