import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../books/domain/book.dart';

final class ChapterBookmarkRepository {
  ChapterBookmarkRepository(this.database);
  final AppDatabase database;

  Stream<Set<String>> watchChapterIds(String bookId) =>
      (database.select(database.chapterBookmarkEntries)
            ..where((entry) => entry.bookId.equals(bookId)))
          .watch()
          .map((entries) => entries.map((entry) => entry.chapterId).toSet());

  Future<void> toggle(String bookId, ChapterMeta chapter) =>
      database.transaction(() async {
        final query = database.select(database.chapterBookmarkEntries)
          ..where(
            (entry) =>
                entry.bookId.equals(bookId) &
                entry.chapterId.equals(chapter.id),
          );
        if (await query.getSingleOrNull() != null) {
          await (database.delete(database.chapterBookmarkEntries)..where(
                (entry) =>
                    entry.bookId.equals(bookId) &
                    entry.chapterId.equals(chapter.id),
              ))
              .go();
        } else {
          await database
              .into(database.chapterBookmarkEntries)
              .insert(
                ChapterBookmarkEntriesCompanion.insert(
                  bookId: bookId,
                  chapterId: chapter.id,
                  chapterIndex: chapter.index,
                  chapterTitle: chapter.title,
                  savedAt: DateTime.now().toUtc(),
                ),
              );
        }
      });
}
