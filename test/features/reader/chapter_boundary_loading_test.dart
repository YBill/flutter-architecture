import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/logic/paragraph_splitter.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';

import 'helpers/reader_test_support.dart';
import 'helpers/test_book_api.dart';

void main() {
  for (final source in ['file cache', 'slow request', 'failed request']) {
    testWidgets('$source: boundary waits quietly, then loads or offers retry', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final book = buildBook(
        id: 'boundary-loading',
        title: 'Book',
        chapters: [
          for (var index = 0; index < 4; index++)
            ChapterData(
              title: 'Chapter ${index + 1}',
              body:
                  '${'Some earlier text. ' * 30}\n\nLast paragraph of chapter ${index + 1}.',
            ),
        ],
      );
      final api = TestBookApi(book);
      final cache = MemoryBookCache();
      final store = MemoryReadingProgressStore();
      final offset = splitParagraphs(book.chapters[1].body).starts.last;
      store.values[book.id] = ReaderPosition(
        chapterIndex: 1,
        charOffset: offset,
        chapterId: book.chapters[1].id,
        contentVersion: book.chapters[1].version,
      );
      final container = ProviderContainer(
        overrides: [
          ...readerTestOverrides(progressStore: store),
          bookApiProvider.overrideWithValue(api),
          bookCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(readerSettingsProvider.notifier)
          .update((s) => s.copyWith(mode: ReaderMode.scroll));
      final repository = container.read(bookRepositoryProvider);
      final detail = await repository.getDetail(book.id);
      final catalog = await repository.getCatalog(detail);
      await repository.getChapter(book.id, catalog.chapters[0]);
      await repository.getChapter(book.id, catalog.chapters[1]);
      if (source == 'file cache') {
        // Separate repository: the next chapter exists in persistent storage,
        // but is deliberately absent from the reader repository's memory.
        await BookRepository(
          api: api,
          cache: cache,
        ).getChapter(book.id, catalog.chapters[2]);
      }
      api.requests.clear();
      final gate = Completer<void>();
      api.beforeChapter = (index) =>
          index == 2 ? gate.future : Future<void>.value();
      if (source == 'failed request') api.failures.add(2);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: ReaderPage(bookId: book.id)),
        ),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('Next chapter'), findsNothing);
        expect(find.text('Previous chapter'), findsNothing);
        expect(find.text('Loading chapter 3…'), findsNothing);
      }
      expect(find.byType(ScrollReader), findsOneWidget);
      expect(find.text('Last paragraph of chapter 2.'), findsOneWidget);
      if (source == 'file cache') {
        expect(find.text('Chapter 3'), findsOneWidget);
        expect(
          api.requests,
          isEmpty,
          reason: 'A file cache hit must not request chapter text',
        );
      } else {
        expect(api.requests, [2]);
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.text('Loading chapter 3…'), findsOneWidget);
        expect(find.text('Last paragraph of chapter 2.'), findsOneWidget);
      }
      gate.complete();
      await tester.pumpAndSettle();
      if (source == 'failed request') {
        expect(find.text('Could not load chapter 3.'), findsOneWidget);
        api.failures.clear();
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(api.requests, [2, 2]);
      }
      expect(find.text('Chapter 3'), findsOneWidget);
      expect(find.text('Loading chapter 3…'), findsNothing);
      final position = container.read(readerPositionProvider(book.id));
      expect(position.chapterIndex, 1);
      expect(position.charOffset, offset);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
