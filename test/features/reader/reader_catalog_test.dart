import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/reader/state/chapter_bookmark_providers.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/reader_sheets.dart';
import 'package:novelverse/features/reader/widgets/reader_theme.dart';

import 'helpers/reader_test_support.dart';

void main() {
  testWidgets(
    'large catalog opens near current chapter with stable bookmarks and builds only visible rows',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final catalog = BookCatalog(
        bookId: 'large-book',
        version: '1',
        chapters: [
          for (var i = 0; i < 2000; i++)
            ChapterMeta(
              id: 'chapter-$i',
              index: i,
              title: 'Chapter ${i + 1}',
              version: '1',
            ),
        ],
      );
      final container = ProviderContainer(overrides: readerTestOverrides());
      container
          .read(readerPositionProvider(catalog.bookId).notifier)
          .update(1499, 0);
      await container
          .read(chapterBookmarkRepositoryProvider)
          .toggle(catalog.bookId, catalog.chapters[1499]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ReaderTheme(child: ReaderCatalogSheet(catalog: catalog)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2000 chapters'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('catalog-chapter-1499')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('catalog-chapter-0')), findsNothing);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      final titleBounds = tester.getRect(find.text('Chapter 1500'));
      final bookmarkBounds = tester.getRect(find.byIcon(Icons.bookmark));
      expect(bookmarkBounds.left - titleBounds.right, inInclusiveRange(6, 10));
      expect(find.byType(ListTile).evaluate().length, lessThan(40));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('settings fit a 320 point viewport', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: readerTestOverrides(),
        child: const MaterialApp(
          home: Scaffold(body: ReaderTheme(child: ReaderSettingsSheet())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Night background'));
    await tester.tap(find.byTooltip('Night background'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Reading settings'))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
