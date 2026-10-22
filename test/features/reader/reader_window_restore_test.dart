import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/reader/logic/paragraph_splitter.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'helpers/reader_test_support.dart';
import 'helpers/test_book_api.dart';

Book makeRestoreBook() => buildBook(
  id: 'restore-window',
  title: 'A Story',
  chapters: [
    for (var chapter = 1; chapter <= 3; chapter++)
      ChapterData(
        title: 'Chapter $chapter',
        body: [
          for (var paragraph = 0; paragraph < 24; paragraph++)
            List.generate(
              5,
              (sentence) =>
                  'Chapter $chapter, paragraph $paragraph, sentence $sentence. A readable sentence with complete English words.',
            ).join(' '),
        ].join('\n\n'),
      ),
  ],
);

void main() {
  testWidgets(
    'inserting a prefetched previous chapter never paints the wrong text for one frame',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final fullBook = makeRestoreBook();
      final container = ProviderContainer(overrides: readerTestOverrides());
      addTearDown(container.dispose);
      container
          .read(readerPositionProvider(fullBook.id).notifier)
          .update(1, splitParagraphs(fullBook.chapters[1].body).starts[8]);
      Book window(List<int> indices) => Book(
        id: fullBook.id,
        title: fullBook.title,
        chapters: [for (final i in indices) fullBook.chapters[i]],
        totalChapters: 3,
      );
      Widget host(Book book) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ScrollReader(book: book, onToggleMenu: () {}),
          ),
        ),
      );
      await tester.pumpWidget(host(window([1])));
      await tester.pumpAndSettle();
      tester
          .widget<ScrollablePositionedList>(
            find.byType(ScrollablePositionedList),
          )
          .itemScrollController!
          .jumpTo(index: 9, alignment: -0.1);
      await tester.pumpAndSettle();

      (String, double) topVisibleText() {
        final viewport = tester.getRect(find.byType(ScrollReader));
        final visible =
            tester
                .widgetList<Text>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is Text && (widget.data?.length ?? 0) > 40,
                  ),
                )
                .map(
                  (text) => (text.data!, tester.getRect(find.byWidget(text))),
                )
                .where((item) => item.$2.overlaps(viewport))
                .toList()
              ..sort((a, b) => a.$2.top.compareTo(b.$2.top));
        expect(visible, isNotEmpty);
        return (visible.first.$1, visible.first.$2.top);
      }

      final anchor = topVisibleText();
      expect(anchor.$1, contains('Chapter 2'));
      final offset = container
          .read(readerPositionProvider(fullBook.id))
          .charOffset;
      // Appending the next chapter must not move the current paragraph.
      await tester.pumpWidget(host(window([1, 2])));
      for (var frame = 0; frame < 3; frame++) {
        final visible = topVisibleText();
        expect(visible.$1, anchor.$1, reason: 'Trailing prefetch frame $frame');
        expect(visible.$2, closeTo(anchor.$2, 0.5));
        await tester.pump();
      }
      // This is the warm-cache reopen case: the saved second chapter appears
      // first, then the cached first chapter is inserted before its list items.
      await tester.pumpWidget(host(window([0, 1, 2])));
      for (var frame = 0; frame < 4; frame++) {
        final visible = topVisibleText();
        expect(
          visible.$1,
          anchor.$1,
          reason: 'Leading prefetch frame $frame must not flash chapter 1',
        );
        expect(visible.$2, closeTo(anchor.$2, 0.5));
        await tester.pump();
      }
      // Removing an earlier chapter from the bounded window must rebase the
      // visible item before paint as well, preserving a partially read block.
      await tester.pumpWidget(host(window([1, 2])));
      for (var frame = 0; frame < 3; frame++) {
        final visible = topVisibleText();
        expect(visible.$1, anchor.$1, reason: 'Window trim frame $frame');
        expect(visible.$2, closeTo(anchor.$2, 0.5));
        await tester.pump();
      }
      expect(
        container.read(readerPositionProvider(fullBook.id)).charOffset,
        offset,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final mode in ReaderMode.values) {
    testWidgets(
      '${mode.name}: reopening a cached second chapter paints only the saved chapter',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        final book = makeRestoreBook();
        final offset = splitParagraphs(book.chapters[1].body).starts[12];
        final progress = MemoryReadingProgressStore();
        progress.values[book.id] = ReaderPosition(
          chapterIndex: 1,
          charOffset: offset,
          chapterId: book.chapters[1].id,
          contentVersion: book.chapters[1].version,
        );
        final container = ProviderContainer(
          overrides: [
            ...readerTestOverrides(progressStore: progress),
            bookApiProvider.overrideWithValue(TestBookApi(book)),
            bookCacheProvider.overrideWithValue(MemoryBookCache()),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(readerSettingsProvider.notifier)
            .update((s) => s.copyWith(mode: mode));
        final repository = container.read(bookRepositoryProvider);
        final detail = await repository.getDetail(book.id);
        final catalog = await repository.getCatalog(detail);
        for (final chapter in catalog.chapters) {
          await repository.getChapter(book.id, chapter);
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: ReaderPage(bookId: book.id)),
          ),
        );
        var readableFrames = 0;
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final viewport = tester.getRect(find.byType(ReaderPage));
          final visible = tester
              .widgetList<Text>(
                find.byWidgetPredicate(
                  (widget) => widget is Text && (widget.data?.length ?? 0) > 40,
                ),
              )
              .where(
                (text) =>
                    tester.getRect(find.byWidget(text)).overlaps(viewport),
              )
              .toList();
          if (visible.isEmpty && readableFrames == 0) continue;
          expect(
            visible,
            isNotEmpty,
            reason: 'Frame $frame must not flash back to loading',
          );
          for (final text in visible) {
            expect(
              text.data,
              contains('Chapter 2'),
              reason: 'Frame $frame must restore chapter 2 before showing text',
            );
          }
          readableFrames++;
        }
        expect(readableFrames, greaterThan(0));
        expect(container.read(readerPositionProvider(book.id)).chapterIndex, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
