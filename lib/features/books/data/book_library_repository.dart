import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/book.dart';

final class BookLibraryRepository {
  BookLibraryRepository(this.database);
  final AppDatabase database;

  Stream<bool> watchIsSaved(String bookId) =>
      (database.select(database.libraryEntries)
            ..where((entry) => entry.bookId.equals(bookId)))
          .watchSingleOrNull()
          .map((entry) => entry != null);

  Future<void> toggle(BookSummary book) => database.transaction(() async {
    final query = database.select(database.libraryEntries)
      ..where((entry) => entry.bookId.equals(book.id));
    if (await query.getSingleOrNull() != null) {
      await (database.delete(
        database.libraryEntries,
      )..where((entry) => entry.bookId.equals(book.id))).go();
    } else {
      await database
          .into(database.libraryEntries)
          .insert(
            LibraryEntriesCompanion.insert(
              bookId: book.id,
              title: book.title,
              author: book.author,
              coverUrl: Value(book.coverUrl),
              savedAt: DateTime.now().toUtc(),
            ),
          );
    }
  });
}
