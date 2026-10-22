import '../reader/helpers/mock_book_api.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/app/app.dart';
import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/books/domain/chapter_preview.dart';
import 'package:novelverse/features/books/presentation/book_detail_page.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';

import '../reader/helpers/reader_test_support.dart';

class FailedRecommendationsApi extends MockBookApi {
  FailedRecommendationsApi() : super(delay: Duration.zero);
  @override
  Future<List<BookRecommendation>> fetchRecommendations(String bookId) async =>
      throw StateError('Recommendations unavailable.');
}

Future<ProviderContainer> showBook(
  WidgetTester tester, {
  BookApi? api,
  MemoryReadingProgressStore? progress,
}) async {
  final container = ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      ...readerTestOverrides(progressStore: progress),
      bookApiProvider.overrideWithValue(
        api ?? MockBookApi(delay: Duration.zero),
      ),
      bookCacheProvider.overrideWithValue(MemoryBookCache()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const NovelverseApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'header scrolls away and toolbar fades in without a system scrim',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetPadding);
      await showBook(tester);

      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('book-detail-scroll')),
          )
          .controller!;
      final header = find.byKey(const ValueKey('book-detail-header'));
      final title = find.byKey(const ValueKey('book-detail-toolbar-title'));
      final initialHeaderTop = tester.getTopLeft(header).dy;
      expect(tester.widget<Opacity>(title).opacity, 0);
      expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
      expect(SystemChrome.latestStyle?.systemStatusBarContrastEnforced, false);

      scroll.jumpTo(72);
      await tester.pump();
      expect(
        tester.widget<Opacity>(title).opacity,
        allOf(greaterThan(0), lessThan(1)),
      );
      expect(tester.getTopLeft(header).dy, closeTo(initialHeaderTop - 72, .1));
      final transitionalBar = tester.widget<SliverAppBar>(
        find.byType(SliverAppBar),
      );
      expect(
        transitionalBar.backgroundColor!.a,
        allOf(greaterThan(0), lessThan(1)),
      );

      scroll.jumpTo(180);
      await tester.pump();
      expect(tester.widget<Opacity>(title).opacity, 1);
      expect(
        tester.widget<SliverAppBar>(find.byType(SliverAppBar)).backgroundColor,
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      );

      scroll.jumpTo(0);
      await tester.pump();
      expect(tester.widget<Opacity>(title).opacity, 0);
      expect(tester.getTopLeft(header).dy, closeTo(initialHeaderTop, .1));
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('real detail displays half a chapter and bookmarks persist', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await showBook(tester);
    final detail = container
        .read(bookDetailProvider(sampleBookId))
        .requireValue;
    expect(find.text(detail.summary.title), findsWidgets);
    expect(find.text('Start Free Reading'), findsOneWidget);
    expect(find.text(detail.summary.author), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('book-synopsis'))).maxLines,
      4,
    );
    await tester.tap(find.byKey(const ValueKey('toggle-synopsis')));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('book-synopsis'))).maxLines,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('toggle-synopsis')));
    await tester.pumpAndSettle();
    expect(find.text('Read more'), findsOneWidget);
    final text = tester
        .widget<Text>(find.byKey(const ValueKey('chapter-preview-text')))
        .data!;
    expect(text, chapterPreview(detail.firstChapter!.body));
    expect(text.length, lessThan(detail.firstChapter!.body.length * .55));
    expect(text.length, greaterThan(detail.firstChapter!.body.length * .3));
    await tester.tap(find.byKey(const ValueKey('save-book')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('save-book')),
        matching: find.byIcon(Icons.favorite_rounded),
      ),
      findsOneWidget,
    );
    expect(
      await container
          .read(bookLibraryRepositoryProvider)
          .database
          .select(
            container
                .read(bookLibraryRepositoryProvider)
                .database
                .libraryEntries,
          )
          .get(),
      hasLength(1),
    );
    await unmount(tester);
  });

  testWidgets(
    'preview CTA resumes saved progress and recommendations open the sample',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = MockBookApi(delay: Duration.zero);
      final detail = await tester.runAsync(() => api.fetchDetail(sampleBookId));
      final first = detail!.firstChapter!;
      final store = MemoryReadingProgressStore();
      store.values[sampleBookId] = ReaderPosition(
        chapterIndex: 0,
        charOffset: 1200,
        chapterId: first.id,
        contentVersion: first.version,
      );
      final container = await showBook(tester, api: api, progress: store);
      await tester.ensureVisible(
        find.byKey(const ValueKey('continue-reading')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('continue-reading')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsOneWidget);
      expect(
        container.read(readerPositionProvider(sampleBookId)).charOffset,
        greaterThan(0),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final card = find.byKey(
        const ValueKey('recommendation-recommendation-1'),
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(
        tester.widget<BookDetailPage>(find.byType(BookDetailPage)).bookId,
        sampleBookId,
      );
      await unmount(tester);
    },
  );

  testWidgets(
    'recommendation failure does not block the detail or reading CTA',
    (tester) async {
      await showBook(tester, api: FailedRecommendationsApi());
      expect(
        find.byKey(const ValueKey('chapter-preview-text')),
        findsOneWidget,
      );
      expect(
        find.text('Could not load recommendations. Retry'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('start-reading')))
            .onPressed,
        isNotNull,
      );
      await unmount(tester);
    },
  );

  testWidgets('narrow layout and larger text do not overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await showBook(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('recommendations')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
