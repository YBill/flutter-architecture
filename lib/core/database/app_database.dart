import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/books/data/library_entries.dart';
import '../../features/reader/data/reading_progress_entries.dart';
import '../../features/reader/data/chapter_bookmark_entries.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [ReadingProgressEntries, LibraryEntries, ChapterBookmarkEntries],
)
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
