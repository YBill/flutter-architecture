import 'package:drift/drift.dart';

class ReadingProgressEntries extends Table {
  TextColumn get bookId => text()();
  TextColumn get chapterId => text()();
  IntColumn get chapterIndex => integer()();
  IntColumn get charOffset => integer()();
  TextColumn get contentVersion => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}
