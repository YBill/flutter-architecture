import 'package:drift/drift.dart';

class LibraryEntries extends Table {
  TextColumn get bookId => text()();
  TextColumn get title => text()();
  TextColumn get author => text()();
  TextColumn get coverUrl => text().nullable()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}
