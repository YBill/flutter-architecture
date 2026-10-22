import 'helpers/mock_book_api.dart';

import 'helpers/reader_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/state/chapter_bookmark_providers.dart';
import 'package:novelverse/features/reader/widgets/paged_reader.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';
import 'package:novelverse/features/reader/widgets/reader_sheets.dart';
import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/books/data/book_cache.dart';

void main() {
  testWidgets('横屏打开Settings并切换行距时不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(750, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...readerTestOverrides(),
          bookCacheProvider.overrideWithValue(MemoryBookCache()),
          bookApiProvider.overrideWithValue(MockBookApi(delay: Duration.zero)),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: sampleBookId)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(375, 195));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Relaxed'));
    await tester.tap(find.text('Relaxed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'reader controls keep the text anchored and persist bookmarks and library',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...readerTestOverrides(),
            bookCacheProvider.overrideWithValue(MemoryBookCache()),
            bookApiProvider.overrideWithValue(
              MockBookApi(delay: Duration.zero),
            ),
          ],
          child: const MaterialApp(home: ReaderPage(bookId: sampleBookId)),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReaderPage)),
      );
      final catalog = container
          .read(bookCatalogProvider(sampleBookId))
          .requireValue;
      expect(
        find.byKey(const ValueKey('reader-chapter-header')),
        findsOneWidget,
      );
      final viewport = tester.getRect(find.byType(PagedReader));
      final compactHeader = tester.getRect(
        find.byKey(const ValueKey('reader-chapter-header')),
      );
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller;
      final offset = container
          .read(readerPositionProvider(sampleBookId))
          .charOffset;
      await tester.tapAt(const Offset(195, 400));
      await tester.pumpAndSettle();
      expect(find.text('Claimed By The Ruthless Alpha'), findsOneWidget);
      expect(find.text('Chapter 1'), findsOneWidget);
      expect(tester.getRect(find.byType(PagedReader)), viewport);
      expect(
        tester.getRect(find.byKey(const ValueKey('reader-chapter-header'))),
        compactHeader,
      );
      final expandedHeader = tester.getRect(
        find.byKey(const ValueKey('reader-expanded-header')),
      );
      expect(expandedHeader.top, compactHeader.top);
      expect(expandedHeader.bottom, greaterThan(compactHeader.bottom));
      expect(
        tester.getCenter(find.byKey(const ValueKey('reader-library'))).dx,
        greaterThan(viewport.center.dx),
      );
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller,
        same(controller),
      );
      expect(
        container.read(readerPositionProvider(sampleBookId)).charOffset,
        offset,
      );

      await tester.tap(find.byTooltip('Add bookmark'));
      await tester.pumpAndSettle();
      expect(
        container.read(chapterBookmarksProvider(sampleBookId)).requireValue,
        {catalog.chapters.first.id},
      );
      expect(find.byTooltip('Remove bookmark'), findsOneWidget);
      await tester.tap(find.byTooltip('Add to library'));
      await tester.pumpAndSettle();
      expect(
        container.read(bookSavedProvider(sampleBookId)).requireValue,
        isTrue,
      );
      await tester.tap(find.text('Contents'));
      await tester.pumpAndSettle();
      expect(find.text('203 chapters'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('catalog-${catalog.chapters.first.id}')),
          matching: find.byIcon(Icons.bookmark),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey('catalog-${catalog.chapters[1].id}')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(readerPositionProvider(sampleBookId)).chapterIndex,
        1,
      );
      expect(find.byTooltip('Add bookmark'), findsOneWidget);

      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      expect(
        container.read(readerSettingsProvider).background,
        ReaderBackground.dark,
      );
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      expect(
        container.read(readerSettingsProvider).background,
        ReaderBackground.paper,
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Brightness affects this reader only.'), findsNothing);
      expect(
        tester.getSize(find.byType(ReaderSettingsSheet)).height,
        lessThan(viewport.height * 0.6),
      );
      for (final background in ReaderBackground.values) {
        await tester.tap(find.byKey(ValueKey('background-${background.name}')));
        await tester.pumpAndSettle();
        expect(container.read(readerSettingsProvider).background, background);
        expect(
          Theme.of(tester.element(find.text('Reading settings'))).brightness,
          background == ReaderBackground.dark
              ? Brightness.dark
              : Brightness.light,
        );
      }
      await tester.tap(find.text('Scroll'));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollReader), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from library'));
      await tester.pumpAndSettle();
      expect(
        container.read(bookSavedProvider(sampleBookId)).requireValue,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
