import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/paged_reader.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';

import 'chapter_loading_test.dart' as loading;
import 'helpers/reader_test_support.dart';
import 'helpers/test_book_api.dart';
import 'scroll_chapter_continuity_test.dart' as support;

PageController pageController(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!;

Future<ProviderContainer> openPagedBoundary(
  WidgetTester tester, {
  required bool forward,
  required TargetPlatform platform,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final book = loading.makeBook(8);
  final container = ProviderContainer(
    overrides: [
      ...readerTestOverrides(),
      bookApiProvider.overrideWithValue(TestBookApi(book)),
      bookCacheProvider.overrideWithValue(MemoryBookCache()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: ReaderPage(
          bookId: book.id,
          initialChapterId: book.chapters[2].id,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (forward) {
    final footer = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => RegExp(r'^1/\d+$').hasMatch(t.data ?? ''));
    final count = int.parse(footer.data!.split('/')[1]);
    final controller = pageController(tester);
    controller.jumpToPage(controller.page!.round() + count - 1);
    await tester.pumpAndSettle();
  }
  return container;
}

void expectSettledChapter(
  WidgetTester tester,
  ProviderContainer container,
  int target,
) {
  expect(
    container.read(readerPositionProvider('large-book')).chapterIndex,
    target,
  );
  expect(pageController(tester).position.isScrollingNotifier.value, isFalse);
  expect(
    pageController(tester).page,
    closeTo(pageController(tester).page!.round(), 0.001),
  );
  final book = tester.widget<PagedReader>(find.byType(PagedReader)).book;
  expect(book.chapters.map((c) => c.index), [target - 1, target, target + 1]);
  final position = container.read(readerPositionProvider('large-book'));
  final remaining = book.chapters[book.localIndex(target)].body
      .substring(position.charOffset)
      .trimRight();
  final body = tester
      .widgetList<Text>(find.byType(Text))
      .where(
        (text) =>
            (text.data?.isNotEmpty ?? false) &&
            remaining.startsWith(text.data!) &&
            tester
                .getRect(find.byWidget(text))
                .overlaps(tester.getRect(find.byType(PagedReader))),
      );
  expect(body, isNotEmpty);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final forward in [true, false]) {
      final label = '${platform.name} ${forward ? "forward" : "backward"}';
      final direction = forward ? -1.0 : 1.0;
      final target = forward ? 3 : 1;
      testWidgets(
        '$label: held cross-chapter drag stays attached and follows the finger',
        (tester) async {
          final container = await openPagedBoundary(
            tester,
            forward: forward,
            platform: platform,
          );
          final before = pageController(tester).position;
          final gesture = await tester.startGesture(const Offset(195, 420));
          for (var i = 0; i < 9; i++) {
            await gesture.moveBy(Offset(direction * 35, 0));
            await tester.pump(const Duration(milliseconds: 16));
          }
          // Allow neighbour prefetch/pagination to finish while the pointer stays down.
          await tester.pumpAndSettle();
          expect(
            container.read(readerPositionProvider('large-book')).chapterIndex,
            target,
          );
          expect(pageController(tester).position, same(before));
          expect(before.isScrollingNotifier.value, isTrue);
          final pixels = before.pixels;
          await gesture.moveBy(Offset(direction * 15, 0));
          await tester.pump();
          expect(before.pixels - pixels, closeTo(-direction * 15, 0.1));
          await gesture.up();
          await tester.pumpAndSettle();
          expectSettledChapter(tester, container, target);
          await support.unmount(tester);
        },
      );

      testWidgets(
        '$label: fling retains its position until page settling finishes',
        (tester) async {
          final container = await openPagedBoundary(
            tester,
            forward: forward,
            platform: platform,
          );
          final before = pageController(tester).position;
          await tester.fling(
            find.byType(PageView),
            Offset(direction * 80, 0),
            1000,
          );
          var sawCrossing = false;
          for (var frame = 0; frame < 80; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            final position = pageController(tester).position;
            if (container
                        .read(readerPositionProvider('large-book'))
                        .chapterIndex ==
                    target &&
                position.isScrollingNotifier.value) {
              sawCrossing = true;
              expect(position, same(before));
              final pixels = position.pixels;
              await tester.pump(const Duration(milliseconds: 16));
              expect(pageController(tester).position, same(before));
              expect((position.pixels - pixels) * -direction, greaterThan(0));
              break;
            }
          }
          expect(sawCrossing, isTrue);
          await tester.pumpAndSettle();
          expectSettledChapter(tester, container, target);
          await support.unmount(tester);
        },
      );
    }

    testWidgets(
      '${platform.name}: reversing a held crossing discards the obsolete window',
      (tester) async {
        final container = await openPagedBoundary(
          tester,
          forward: true,
          platform: platform,
        );
        final gesture = await tester.startGesture(const Offset(195, 420));
        for (var i = 0; i < 9; i++) {
          await gesture.moveBy(const Offset(-35, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        expect(
          container.read(readerPositionProvider('large-book')).chapterIndex,
          3,
        );
        await gesture.moveBy(const Offset(250, 0));
        await tester.pumpAndSettle();
        expect(
          container.read(readerPositionProvider('large-book')).chapterIndex,
          2,
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expectSettledChapter(tester, container, 2);
        await support.unmount(tester);
      },
    );

    testWidgets(
      '${platform.name}: explicit chapter navigation overrides a deferred window',
      (tester) async {
        final container = await openPagedBoundary(
          tester,
          forward: true,
          platform: platform,
        );
        final gesture = await tester.startGesture(const Offset(195, 420));
        for (var i = 0; i < 9; i++) {
          await gesture.moveBy(const Offset(-35, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        expect(
          container.read(readerPositionProvider('large-book')).chapterIndex,
          3,
        );
        container
            .read(readerJumpProvider('large-book').notifier)
            .jumpToChapter(4);
        await tester.pumpAndSettle();
        await gesture.cancel();
        await tester.pumpAndSettle();
        expectSettledChapter(tester, container, 4);
        await support.unmount(tester);
      },
    );

    testWidgets(
      '${platform.name}: compaction distinguishes the first text block from its header',
      (tester) async {
        final book = buildBook(
          id: 'chapter-continuity',
          title: 'Short',
          chapters: [
            for (var i = 0; i < 30; i++)
              ChapterData(
                title: 'Chapter ${i + 1}',
                body:
                    'Chapter ${i + 1} paragraph 0. ${'The path continues through the forest without stopping. ' * 16}',
              ),
          ],
        );
        final container = await support.openAtBoundary(
          tester,
          forward: true,
          platform: platform,
          sourceBook: book,
        );
        final gesture = await tester.startGesture(const Offset(195, 420));
        Finder? anchor;
        double? y;
        for (var i = 0; i < 500; i++) {
          await gesture.moveBy(const Offset(0, -15));
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump();
          final position = container.read(readerPositionProvider(book.id));
          if (position.chapterIndex == 10 && position.charOffset == 0) {
            final candidates = find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  (w.data ?? '').startsWith('Chapter 11 paragraph 0.'),
            );
            if (candidates.evaluate().isNotEmpty) {
              final top = tester.getTopLeft(candidates.first).dy;
              if (top < tester.getTopLeft(find.byType(ScrollReader)).dy - 10) {
                anchor = candidates.first;
                y = top;
                break;
              }
            }
          }
        }
        expect(anchor, isNotNull);
        // Cancel rather than fling so any movement comes from compaction alone.
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(anchor!).dy, closeTo(y!, 1));
        expect(
          container.read(readerPositionProvider(book.id)).chapterIndex,
          10,
        );
        // Layout changes must preserve the text-block identity as well.
        container
            .read(readerSettingsProvider.notifier)
            .update((s) => s.copyWith(fontSize: 24));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(anchor).dy,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byType(ScrollReader)).dy + 1,
          ),
        );
        // An intentional jump to the same chapter still selects its title.
        container.read(readerJumpProvider(book.id).notifier).jumpToChapter(10);
        await tester.pumpAndSettle();
        final title = find.descendant(
          of: find.byType(ScrollReader),
          matching: find.text('Chapter 11'),
        );
        expect(
          tester.getTopLeft(title).dy,
          greaterThanOrEqualTo(tester.getTopLeft(find.byType(ScrollReader)).dy),
        );
        expect(tester.takeException(), isNull);
        await support.unmount(tester);
      },
    );
  }
}
