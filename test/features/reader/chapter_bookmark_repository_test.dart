import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/core/database/app_database.dart';
import 'package:novelverse/features/books/data/book_library_repository.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/reader/data/chapter_bookmark_repository.dart';

void main() {
  test('bookmarks and library survive reopening and toggle independently by book and stable chapter ID', () async {
    final directory = Directory.systemTemp.createTempSync('reader-bookmarks-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/reader.sqlite');
    var database = AppDatabase(NativeDatabase(file));
    const chapter = ChapterMeta(
      id: 'chapter-150',
      index: 149,
      title: 'A New Dawn',
      version: '1',
    );
    const book = BookSummary(
      id: 'book-a',
      title: 'A Story',
      author: 'An Author',
      chapterCount: 2000,
    );
    var bookmarks = ChapterBookmarkRepository(database);
    await bookmarks.toggle(book.id, chapter);
    await bookmarks.toggle('book-b', chapter);
    await BookLibraryRepository(database).toggle(book);
    await database.close();

    database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    bookmarks = ChapterBookmarkRepository(database);
    expect(await bookmarks.watchChapterIds(book.id).first, {chapter.id});
    expect(
      await BookLibraryRepository(database).watchIsSaved(book.id).first,
      isTrue,
    );
    final row = await database.select(database.chapterBookmarkEntries).get();
    expect(row.first.chapterIndex, 149);
    expect(row.first.chapterTitle, chapter.title);
    expect(row.first.savedAt, isNotNull);

    // A catalog reorder keeps the existing identity; toggling removes it.
    await bookmarks.toggle(
      book.id,
      const ChapterMeta(
        id: 'chapter-150',
        index: 151,
        title: 'Renamed',
        version: '2',
      ),
    );
    expect(await bookmarks.watchChapterIds(book.id).first, isEmpty);
    expect(await bookmarks.watchChapterIds('book-b').first, {chapter.id});
    expect(
      await BookLibraryRepository(database).watchIsSaved(book.id).first,
      isTrue,
    );
    await BookLibraryRepository(database).toggle(book);
    expect(
      await BookLibraryRepository(database).watchIsSaved(book.id).first,
      isFalse,
    );
  });
}
