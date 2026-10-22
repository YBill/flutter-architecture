import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/core/database/app_database.dart';
import 'package:novelverse/features/books/data/book_library_repository.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/reader/data/reading_progress_store.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';

import 'helpers/reader_test_support.dart';

BookCatalog catalog(List<String> ids, {String version = 'v1'}) => BookCatalog(
  bookId: 'book',
  version: version,
  chapters: [
    for (var i = 0; i < ids.length; i++)
      ChapterMeta(id: ids[i], index: i, title: 'Chapter $i', version: version),
  ],
);

class DelayedProgressStore extends MemoryReadingProgressStore {
  final started = Completer<void>();
  final release = Completer<void>();
  int writes = 0;

  @override
  Future<void> write(String bookId, ReaderPosition position) async {
    if (writes++ == 0) {
      started.complete();
      await release.future;
    }
    await super.write(bookId, position);
  }
}

void main() {
  test(
    'progress and library survive closing and reopening the database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'novelverse-progress-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/reading.sqlite');
      final first = AppDatabase(NativeDatabase(file));
      const position = ReaderPosition(
        chapterIndex: 1499,
        charOffset: 3241,
        chapterId: 'chapter-1500',
        contentVersion: 'text-v1',
      );
      await DriftReadingProgressStore(first).write('book', position);
      await DriftReadingProgressStore(first).write(
        'other',
        const ReaderPosition(
          chapterIndex: 2,
          charOffset: 8,
          chapterId: 'other-3',
          contentVersion: 'v1',
        ),
      );
      await BookLibraryRepository(first).toggle(
        const BookSummary(
          id: 'book',
          title: 'Book',
          author: 'Author',
          chapterCount: 2000,
        ),
      );
      await first.close();

      final second = AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      final restored = await DriftReadingProgressStore(second).read('book');
      expect(restored?.chapterId, 'chapter-1500');
      expect(restored?.charOffset, 3241);
      expect(restored?.chapterIndex, 1499);
      expect(
        (await DriftReadingProgressStore(second).read('other'))?.charOffset,
        8,
      );
      expect(await second.select(second.libraryEntries).get(), hasLength(1));
    },
  );

  test(
    'stable chapter IDs follow catalog insertions; changed text resets offset',
    () async {
      final store = MemoryReadingProgressStore();
      store.values['book'] = const ReaderPosition(
        chapterIndex: 1,
        charOffset: 80,
        chapterId: 'target',
        contentVersion: 'v1',
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final listener = container.listen(
        readerPositionProvider('book'),
        (_, next) {},
      );
      addTearDown(listener.close);
      final controller = container.read(
        readerPositionProvider('book').notifier,
      );
      await controller.restore(store);
      controller.bindCatalog(catalog(['new', 'old', 'target']));
      expect(container.read(readerPositionProvider('book')).chapterIndex, 2);
      expect(container.read(readerPositionProvider('book')).charOffset, 80);
      controller.bindCatalog(catalog(['new', 'old', 'target'], version: 'v2'));
      expect(container.read(readerPositionProvider('book')).charOffset, 0);
    },
  );

  test(
    'unloaded or failed chapter navigation cannot overwrite saved progress',
    () async {
      final store = MemoryReadingProgressStore();
      store.values['book'] = const ReaderPosition(
        chapterIndex: 0,
        charOffset: 20,
        chapterId: 'one',
        contentVersion: 'v1',
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final listener = container.listen(
        readerPositionProvider('book'),
        (_, next) {},
      );
      addTearDown(listener.close);
      final controller = container.read(
        readerPositionProvider('book').notifier,
      );
      await controller.restore(store);
      controller.bindCatalog(catalog(['one', 'two']));
      controller.registerChapter(
        Chapter(
          id: 'one',
          index: 0,
          title: 'One',
          body: 'a' * 100,
          version: 'v1',
        ),
      );
      controller.update(1, 0); // Target failed to load.
      await controller.flush();
      expect(store.values['book']?.chapterId, 'one');
      expect(store.values['book']?.charOffset, 20);
    },
  );

  test(
    'serialized flushes keep the newest position when a write is slow',
    () async {
      final store = DelayedProgressStore();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final listener = container.listen(
        readerPositionProvider('book'),
        (_, next) {},
      );
      addTearDown(listener.close);
      final controller = container.read(
        readerPositionProvider('book').notifier,
      );
      await controller.restore(store);
      controller.bindCatalog(catalog(['one']));
      controller.registerChapter(
        Chapter(
          id: 'one',
          index: 0,
          title: 'One',
          body: 'a' * 1000,
          version: 'v1',
        ),
      );
      controller.update(0, 120);
      final first = controller.flush();
      await store.started.future;
      controller.update(0, 600);
      final second = controller.flush();
      store.release.complete();
      await Future.wait([first, second]);
      expect(store.values['book']?.charOffset, 600);
    },
  );
}
