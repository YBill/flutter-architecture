import 'helpers/reader_test_support.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/reader/logic/paragraph_splitter.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/paged_reader.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';

import 'helpers/test_book_api.dart';

Future<void> frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Book makeBook(int count) => buildBook(
  id: 'large-book',
  title: 'Large English Book',
  chapters: List.generate(
    count,
    (i) => ChapterData(
      title: 'Chapter ${i + 1}',
      body: List.generate(
        12,
        (p) =>
            'Chapter ${i + 1}, paragraph $p. ${'A sentence with complete English words and enough text for several pages. ' * 4}',
      ).join('\n\n'),
    ),
  ),
);

void main() {
  for (final mode in ReaderMode.values) {
    testWidgets('${mode.name}: crossing chapters preserves the moving window', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final book = makeBook(8);
      final api = TestBookApi(book);
      final container = ProviderContainer(
        overrides: [
          ...readerTestOverrides(),
          bookApiProvider.overrideWithValue(api),
          bookCacheProvider.overrideWithValue(MemoryBookCache()),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(readerSettingsProvider.notifier)
          .update((s) => s.copyWith(mode: mode));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ReaderPage(
              bookId: book.id,
              initialChapterId: book.chapters[2].id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> crossTo(int target) async {
        if (mode == ReaderMode.paged) {
          for (var step = 0; step < 100; step++) {
            final current = container.read(readerPositionProvider(book.id));
            if (current.chapterIndex == target) break;
            final controller = tester
                .widget<PageView>(find.byType(PageView))
                .controller!;
            controller.jumpToPage(
              controller.page!.round() +
                  (target > current.chapterIndex ? 1 : -1),
            );
            await tester.pumpAndSettle();
          }
        } else {
          final window = tester
              .widget<ScrollReader>(find.byType(ScrollReader))
              .book;
          var item = window.chapters.first.index > 0 ? 1 : 0;
          for (final chapter in window.chapters) {
            if (chapter.index == target) break;
            item += 1 + splitParagraphs(chapter.body).texts.length;
          }
          tester
              .widget<ScrollablePositionedList>(
                find.byType(ScrollablePositionedList),
              )
              .itemScrollController!
              .jumpTo(index: item);
          await tester.pumpAndSettle();
        }
        expect(
          container.read(readerPositionProvider(book.id)).chapterIndex,
          target,
        );
        final window = mode == ReaderMode.paged
            ? tester.widget<PagedReader>(find.byType(PagedReader)).book
            : tester.widget<ScrollReader>(find.byType(ScrollReader)).book;
        expect(window.chapters.map((c) => c.index), [
          target - 1,
          target,
          target + 1,
        ]);
        expect(tester.takeException(), isNull);
      }

      await crossTo(3);
      await crossTo(4);
      await crossTo(3);
      await crossTo(2);
      expect(api.requests.toSet(), {1, 2, 3, 4, 5});
      expect(
        api.requests.length,
        5,
        reason: 'Reading back must reuse cached chapters',
      );
    });

    testWidgets(
      '${mode.name}: chapter 1500 opens first, then only its neighbours are fetched',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final book = makeBook(2000);
        final api = TestBookApi(book);
        final gates = {
          for (final i in [1498, 1499, 1500]) i: Completer<void>(),
        };
        api.beforeChapter = (i) => gates[i]?.future ?? Future<void>.value();
        final container = ProviderContainer(
          overrides: [
            ...readerTestOverrides(),
            bookApiProvider.overrideWithValue(api),
            bookCacheProvider.overrideWithValue(MemoryBookCache()),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(readerSettingsProvider.notifier)
            .update((s) => s.copyWith(mode: mode));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: ReaderPage(
                bookId: book.id,
                initialChapterId: book.chapters[1499].id,
              ),
            ),
          ),
        );
        await frames(tester);
        expect(api.requests, [1499]);
        expect(find.text('Loading chapter 1500…'), findsOneWidget);
        gates[1499]!.complete();
        await frames(tester);
        expect(api.requests.toSet(), {1498, 1499, 1500});
        Book window() => mode == ReaderMode.paged
            ? tester.widget<PagedReader>(find.byType(PagedReader)).book
            : tester.widget<ScrollReader>(find.byType(ScrollReader)).book;
        expect(window().chapters.map((c) => c.index), [
          1499,
        ], reason: 'Neighbour requests must not block the target chapter');
        // Start reading before neighbours complete; inserting an earlier
        // chapter must preserve a partially visible paragraph or current page.
        if (mode == ReaderMode.paged) {
          tester
              .widget<PageView>(find.byType(PageView))
              .controller!
              .jumpToPage(2);
        } else {
          tester
              .widget<ScrollablePositionedList>(
                find.byType(ScrollablePositionedList),
              )
              .itemScrollController!
              .jumpTo(index: 8, alignment: -0.15);
        }
        await frames(tester);
        final position = container.read(readerPositionProvider(book.id));
        expect(position.charOffset, greaterThan(0));
        gates[1498]!.complete();
        gates[1500]!.complete();
        await tester.pumpAndSettle();
        expect(window().chapters.map((c) => c.index), [1498, 1499, 1500]);
        expect(
          container.read(readerPositionProvider(book.id)).chapterIndex,
          1499,
        );
        expect(
          container.read(readerPositionProvider(book.id)).charOffset,
          position.charOffset,
        );
        container
            .read(readerJumpProvider(book.id).notifier)
            .jumpToChapter(1500);
        await tester.pumpAndSettle();
        expect(
          container.read(readerPositionProvider(book.id)).chapterIndex,
          1500,
        );
        expect(api.requests.toSet(), {1498, 1499, 1500, 1501});
        expect(window().chapters, hasLength(3));
        final requests = api.requests.length;
        container
            .read(readerSettingsProvider.notifier)
            .update(
              (s) => s.copyWith(
                mode: mode == ReaderMode.paged
                    ? ReaderMode.scroll
                    : ReaderMode.paged,
                fontSize: 24,
              ),
            );
        await tester.pumpAndSettle();
        expect(
          api.requests,
          hasLength(requests),
          reason: 'Layout changes must reuse fetched text',
        );
        expect(
          container.read(readerPositionProvider(book.id)).chapterIndex,
          1500,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'late responses from an old jump cannot replace the newly selected chapter',
    (tester) async {
      final book = makeBook(30);
      final api = TestBookApi(book);
      final old = Completer<void>();
      api.beforeChapter = (i) => i == 5 ? old.future : Future<void>.value();
      final container = ProviderContainer(
        overrides: [
          ...readerTestOverrides(),
          bookApiProvider.overrideWithValue(api),
          bookCacheProvider.overrideWithValue(MemoryBookCache()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: ReaderPage(bookId: book.id)),
        ),
      );
      await tester.pumpAndSettle();
      container.read(readerJumpProvider(book.id).notifier).jumpToChapter(5);
      await frames(tester);
      container.read(readerJumpProvider(book.id).notifier).jumpToChapter(20);
      await tester.pumpAndSettle();
      old.complete();
      await tester.pumpAndSettle();
      expect(container.read(readerPositionProvider(book.id)).chapterIndex, 20);
      final window = tester.widget<PagedReader>(find.byType(PagedReader)).book;
      expect(window.chapters.map((c) => c.index), [19, 20, 21]);
    },
  );

  testWidgets(
    'prefetch failure leaves current text readable and failed navigation supports retry',
    (tester) async {
      final book = makeBook(4);
      final api = TestBookApi(book)..failures.add(1);
      final container = ProviderContainer(
        overrides: [
          ...readerTestOverrides(),
          bookApiProvider.overrideWithValue(api),
          bookCacheProvider.overrideWithValue(MemoryBookCache()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: ReaderPage(bookId: book.id)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PagedReader), findsOneWidget);
      expect(container.read(readerPositionProvider(book.id)).chapterIndex, 0);
      container.read(readerJumpProvider(book.id).notifier).jumpToChapter(1);
      await tester.pumpAndSettle();
      expect(find.text('Could not load chapter 2.'), findsOneWidget);
      api.failures.clear();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(container.read(readerPositionProvider(book.id)).chapterIndex, 1);
      expect(find.byType(PagedReader), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
