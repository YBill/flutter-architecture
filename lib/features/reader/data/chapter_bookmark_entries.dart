import 'package:drift/drift.dart';

/// Chapter identity is stable even if the server reorders its catalog.
class ChapterBookmarkEntries extends Table {
  TextColumn get bookId => text()();
  TextColumn get chapterId => text()();
  IntColumn get chapterIndex => integer()();
  TextColumn get chapterTitle => text()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId, chapterId};
}
