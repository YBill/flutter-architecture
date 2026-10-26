import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/paged_reader.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';
import 'package:novelverse/features/reader/widgets/reader_scroll_list.dart';

import 'helpers/reader_test_support.dart';
import 'helpers/test_book_api.dart';

class UpdatingBookApi extends TestBookApi {
  UpdatingBookApi()
    : super(
        buildBook(
          id: 'updating-book',
          title: 'Book',
          chapters: [
            for (var i = 0; i < 7; i++)
              ChapterData(
                title: 'Chapter ${i + 1}',
                body: 'Original chapter $i. ' * 100,
              ),
          ],
        ),
      );

  int revision = 1;
  int detailRequests = 0;
  bool failDetail = false;
  Future<void>? detailGate;
  Future<void>? oldChapterGate;
  String? delayedChapterId;

  void updateChapter(int index, {bool insertBefore = false}) {
    revision++;
    final old = book.chapters[index];
    book.chapters[index] = Chapter(
      id: old.id,
      index: index,
      title: old.title,
      body: 'Updated chapter $index. ' * 100,
      version: 'v$revision',
    );
    if (insertBefore) {
      book.chapters.insert(
        0,
        const Chapter(
          id: 'new-intro',
          index: 0,
          title: 'Introduction',
          body: 'An introduction.',
          version: 'v2',
        ),
      );
      for (var i = 1; i < book.chapters.length; i++) {
        final chapter = book.chapters[i];
        book.chapters[i] = Chapter(
          id: chapter.id,
          index: i,
          title: chapter.title,
          body: chapter.body,
          version: chapter.version,
        );
      }
    }
  }

  @override
  Future<BookDetail> fetchDetail(String bookId) async {
    detailRequests++;
    if (detailGate != null) await detailGate;
    if (failDetail) throw StateError('Temporary detail failure');
    return BookDetail(
      summary: summary,
      description: 'Book',
      status: 'Ongoing',
      category: 'Fiction',
      tags: [],
      catalogVersion: 'catalog-v$revision',
    );
  }

  @override
  Future<BookCatalog> fetchCatalog(String bookId) async {
    final result = await super.fetchCatalog(bookId);
    return BookCatalog(
      bookId: bookId,
      version: 'catalog-v$revision',
      chapters: result.chapters,
    );
  }

  @override
  Future<Chapter> fetchChapter(String bookId, ChapterMeta meta) async {
    // Capture an old response before the server update, then release it after
    // the refreshed reader is displayed to test epoch protection.
    if (meta.id == delayedChapterId && oldChapterGate != null) {
      requests.add(meta.index);
      final chapter = book.chapters.firstWhere((c) => c.id == meta.id);
      await oldChapterGate;
      return chapter;
    }
    return super.fetchChapter(bookId, meta);
  }
}

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<ProviderContainer> openReader(
  WidgetTester tester,
  UpdatingBookApi api,
  ReaderMode mode, {
  String? initialChapterId,
}) async {
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
          bookId: api.book.id,
          initialChapterId: initialChapterId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Book window(WidgetTester tester, ReaderMode mode) => mode == ReaderMode.paged
    ? tester.widget<PagedReader>(find.byType(PagedReader)).book
    : tester.widget<ScrollReader>(find.byType(ScrollReader)).book;

Future<void> closeReader(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  for (final mode in ReaderMode.values) {
    testWidgets(
      '${mode.name}: version retry follows chapter ID after insertion',
      (tester) async {
        final api = UpdatingBookApi();
        final container = await openReader(
          tester,
          api,
          mode,
          initialChapterId: api.book.chapters[1].id,
        );
        final targetId = api.book.chapters[4].id;
        api.updateChapter(4, insertBefore: true);
        container
            .read(readerJumpProvider(api.book.id).notifier)
            .jumpToChapter(4);
        await tester.pumpAndSettle();
        expect(find.text('Could not load chapter 5.'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        final position = container.read(readerPositionProvider(api.book.id));
        expect(position.chapterId, targetId);
        expect(position.chapterIndex, 5);
        expect(position.contentVersion, 'v2');
        expect(position.charOffset, 0);
        expect(window(tester, mode).chapters.map((c) => c.index), [4, 5, 6]);
        expect(
          window(
            tester,
            mode,
          ).chapters.firstWhere((c) => c.id == targetId).body,
          startsWith('Updated chapter 4.'),
        );
        expect(api.detailRequests, 2);
        expect(api.catalogRequests, 2);
        await closeReader(tester);
      },
    );

    testWidgets(
      '${mode.name}: failed metadata refresh can be retried without a loop',
      (tester) async {
        final api = UpdatingBookApi();
        final container = await openReader(
          tester,
          api,
          mode,
          initialChapterId: api.book.chapters[1].id,
        );
        final targetId = api.book.chapters[4].id;
        api.updateChapter(4);
        container
            .read(readerJumpProvider(api.book.id).notifier)
            .jumpToChapter(4);
        await tester.pumpAndSettle();
        api.failDetail = true;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('Could not open this book. Retry'), findsOneWidget);
        final attempts = api.detailRequests;
        await tester.pump(const Duration(seconds: 2));
        expect(api.detailRequests, attempts);
        api.failDetail = false;
        await tester.tap(find.text('Could not open this book. Retry'));
        await tester.pumpAndSettle();
        expect(
          container.read(readerPositionProvider(api.book.id)).chapterId,
          targetId,
        );
        expect(
          window(
            tester,
            mode,
          ).chapters.firstWhere((c) => c.id == targetId).version,
          'v2',
        );
        await closeReader(tester);
      },
    );

    testWidgets('${mode.name}: ordinary failures retry only the chapter', (
      tester,
    ) async {
      final api = UpdatingBookApi();
      final container = await openReader(tester, api, mode);
      api.failures.add(4);
      container.read(readerJumpProvider(api.book.id).notifier).jumpToChapter(4);
      await tester.pumpAndSettle();
      api.failures.clear();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        container.read(readerPositionProvider(api.book.id)).chapterIndex,
        4,
      );
      expect(api.detailRequests, 1);
      expect(api.catalogRequests, 1);
      await closeReader(tester);
    });
  }

  testWidgets(
    'another server update during retry stops at a recoverable error',
    (tester) async {
      final api = UpdatingBookApi();
      final container = await openReader(tester, api, ReaderMode.paged);
      api.updateChapter(4);
      container.read(readerJumpProvider(api.book.id).notifier).jumpToChapter(4);
      await tester.pumpAndSettle();
      api.beforeChapter = (index) async {
        if (index == 4) api.updateChapter(4);
      };
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load chapter 5.'), findsOneWidget);
      final requests = api.requests.length;
      await tester.pump(const Duration(seconds: 2));
      expect(api.requests.length, requests);
      expect(api.detailRequests, 2);
      api.beforeChapter = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        container.read(readerPositionProvider(api.book.id)).contentVersion,
        'v3',
      );
      await closeReader(tester);
    },
  );

  testWidgets(
    'prefetch version retry preserves current chapter; late old response is ignored',
    (tester) async {
      final api = UpdatingBookApi();
      final oldResponse = Completer<void>();
      api.delayedChapterId = api.book.chapters[0].id;
      api.oldChapterGate = oldResponse.future;
      final currentId = api.book.chapters[1].id;
      api.book.chapters[1] = Chapter(
        id: currentId,
        index: 1,
        title: 'Chapter 2',
        body: 'Current chapter text.\n\nEnd of current chapter.',
      );
      final nextResponse = Completer<void>();
      api.beforeChapter = (index) =>
          index == 2 ? nextResponse.future : Future<void>.value();
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
          .update((s) => s.copyWith(mode: ReaderMode.scroll));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ReaderPage(bookId: api.book.id, initialChapterId: currentId),
          ),
        ),
      );
      await pumpFrames(tester);
      expect(api.requests.toSet(), {0, 1, 2});
      tester
          .widget<ReaderScrollList>(find.byType(ReaderScrollList))
          .itemScrollController
          .jumpTo(index: 3);
      await pumpFrames(tester);
      final offset = container
          .read(readerPositionProvider(api.book.id))
          .charOffset;
      expect(offset, greaterThan(0));
      api.updateChapter(2, insertBefore: true);
      nextResponse.complete();
      await pumpFrames(tester);
      expect(find.text('Could not load chapter 3.'), findsOneWidget);
      final refreshing = Completer<void>();
      api.detailGate = refreshing.future;
      await tester.tap(find.text('Retry'));
      await pumpFrames(tester);
      api.oldChapterGate = null;
      refreshing.complete();
      await pumpFrames(tester);
      expect(window(tester, ReaderMode.scroll).chapters.map((c) => c.index), [
        1,
        2,
        3,
      ]);
      final position = container.read(readerPositionProvider(api.book.id));
      expect(position.chapterId, currentId);
      expect(position.chapterIndex, 2);
      expect(position.charOffset, offset);
      oldResponse.complete();
      await tester.pumpAndSettle();
      expect(window(tester, ReaderMode.scroll).chapters.map((c) => c.index), [
        1,
        2,
        3,
      ]);
      expect(
        container.read(readerPositionProvider(api.book.id)).chapterIndex,
        2,
      );
      await closeReader(tester);
    },
  );
}
