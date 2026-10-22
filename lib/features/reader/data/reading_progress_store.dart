import '../../../core/database/app_database.dart';
import '../domain/reading_position.dart';

abstract interface class ReadingProgressStore {
  Future<ReaderPosition?> read(String bookId);
  Future<void> write(String bookId, ReaderPosition position);
}

final class DriftReadingProgressStore implements ReadingProgressStore {
  DriftReadingProgressStore(this.database);
  final AppDatabase database;

  @override
  Future<ReaderPosition?> read(String bookId) async {
    final row = await (database.select(
      database.readingProgressEntries,
    )..where((entry) => entry.bookId.equals(bookId))).getSingleOrNull();
    return row == null
        ? null
        : ReaderPosition(
            chapterId: row.chapterId,
            chapterIndex: row.chapterIndex,
            charOffset: row.charOffset,
            contentVersion: row.contentVersion,
          );
  }

  @override
  Future<void> write(String bookId, ReaderPosition position) => database
      .into(database.readingProgressEntries)
      .insertOnConflictUpdate(
        ReadingProgressEntriesCompanion.insert(
          bookId: bookId,
          chapterId: position.chapterId!,
          chapterIndex: position.chapterIndex,
          charOffset: position.charOffset,
          contentVersion: position.contentVersion!,
          updatedAt: DateTime.now().toUtc(),
        ),
      )
      .then((_) {});
}
