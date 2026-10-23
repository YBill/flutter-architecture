import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/reader/logic/paragraph_splitter.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/reader_scroll_list.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';

import 'scroll_chapter_continuity_test.dart' as support;

Map<String, double> visibleAnchors(WidgetTester tester) {
  final viewport = tester.getRect(find.byType(ScrollReader));
  final result = <String, double>{};
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final data = text.data;
    if (data == null || data.length < 50 || !data.startsWith('Chapter ')) {
      continue;
    }
    final rect = tester.getRect(find.byWidget(text));
    if (rect.overlaps(viewport)) result[data] = rect.top;
  }
  return result;
}

ThemeData readerThemeData(WidgetTester tester) => tester
    .element(find.byType(ReaderScrollList))
    .findAncestorWidgetOfExactType<Theme>()!
    .data;

int windowItemCount(Book window) =>
    (window.chapters.first.index > 0 ? 1 : 0) +
    (window.chapters.last.index < window.chapterCount - 1 ? 1 : 0) +
    window.chapters.fold<int>(
      0,
      (count, chapter) =>
          count + 1 + splitParagraphs(chapter.body).texts.length,
    );

Map<String, RenderObject> visibleTextObjects(WidgetTester tester) => {
  for (final text in visibleAnchors(tester).keys)
    text: tester.renderObject(find.text(text)),
};

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final forward in [true, false]) {
      testWidgets('${platform.name} ${forward ? 'forward' : 'backward'}: '
          'chapter labels reuse the palette and visible text layouts', (
        tester,
      ) async {
        final container = await support.openAtBoundary(
          tester,
          forward: forward,
          platform: platform,
        );
        final position = support.scrollPosition(tester);
        expect(
          position.physics,
          platform == TargetPlatform.iOS
              ? isA<BouncingScrollPhysics>()
              : isA<ClampingScrollPhysics>(),
        );
        final palette = readerThemeData(tester);
        final shell = tester.widget<Scaffold>(find.byType(Scaffold).last);
        final before = {
          for (final text in visibleAnchors(tester).keys)
            text: tester.renderObject(find.text(text)),
        };
        final target = forward ? 9 : 8;
        final direction = forward ? -1.0 : 1.0;
        final gesture = await tester.startGesture(const Offset(195, 420));
        for (var frame = 0; frame < 40; frame++) {
          await gesture.moveBy(Offset(0, direction * 40));
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump();
          if (container
                  .read(readerPositionProvider('chapter-continuity'))
                  .chapterIndex ==
              target) {
            break;
          }
        }
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          container
              .read(readerPositionProvider('chapter-continuity'))
              .chapterIndex,
          target,
        );
        expect(readerThemeData(tester), same(palette));
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).last),
          same(shell),
          reason:
              'Chapter and prefetch updates must not rebuild the page shell',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('reader-chapter-header')),
            matching: find.text('Chapter ${target + 1}'),
          ),
          findsOneWidget,
        );
        final common = visibleAnchors(tester).keys
            .where(before.containsKey)
            .toList();
        expect(common, isNotEmpty);
        for (final text in common) {
          expect(
            tester.renderObject(find.text(text)),
            same(before[text]),
            reason: 'A chapter label update must not replace visible text',
          );
        }
        var previousObjects = visibleTextObjects(tester);
        final furtherTarget = target + (forward ? 2 : -2);
        for (var frame = 0; frame < 240; frame++) {
          if (container
                  .read(readerPositionProvider('chapter-continuity'))
                  .chapterIndex ==
              furtherTarget) {
            break;
          }
          await gesture.moveBy(Offset(0, direction * 160));
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump();
          final objects = visibleTextObjects(tester);
          for (final text in objects.keys.where(previousObjects.containsKey)) {
            expect(
              objects[text],
              same(previousObjects[text]),
              reason: 'Continuous scrolling must retain visible layouts across every window update',
            );
          }
          previousObjects = objects;
        }
        expect(
          container
              .read(readerPositionProvider('chapter-continuity'))
              .chapterIndex,
          furtherTarget,
        );
        await gesture.up();
        await tester.pumpAndSettle();
        final window = tester
            .widget<ScrollReader>(find.byType(ScrollReader))
            .book;
        final expectedCount = windowItemCount(window);
        expect(
          tester
              .widget<ReaderScrollList>(find.byType(ReaderScrollList))
              .itemCount,
          expectedCount,
          reason: 'The temporary buffer must be released once scrolling ends',
        );
        await support.unmount(tester);
      });

      testWidgets('${platform.name} ${forward ? 'forward' : 'backward'}: '
          'fling has no stationary frames when the chapter changes', (
        tester,
      ) async {
        await support.openAtBoundary(
          tester,
          forward: forward,
          platform: platform,
        );
        final direction = forward ? -1.0 : 1.0;
        await tester.fling(
          find.byType(ScrollReader),
          Offset(0, direction * 80),
          2200,
        );
        // The first ticker frame establishes the animation clock.
        await tester.pump(const Duration(milliseconds: 16));
        var previous = visibleAnchors(tester);
        final stalls = <String>[];
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final current = visibleAnchors(tester);
          final common = previous.keys.where(current.containsKey).toList();
          expect(common, isNotEmpty, reason: 'Frame $frame lost visible text');
          final distance =
              (current[common.first]! - previous[common.first]!) * direction;
          if (distance < 0.5) {
            stalls.add('$frame: ${distance.toStringAsFixed(3)}px');
          }
          previous = current;
        }
        expect(stalls, isEmpty, reason: 'Stationary/backward frames: $stalls');
        await tester.pumpAndSettle();
        await support.unmount(tester);
      });
    }
  }

  testWidgets('a very long drag keeps a bounded buffer and releases it on idle', (
    tester,
  ) async {
    final book = buildBook(
      id: 'chapter-continuity',
      title: 'Short Chapters',
      chapters: [
        for (var i = 0; i < 40; i++)
          ChapterData(
            title: 'Chapter ${i + 1}',
            body:
                'Chapter ${i + 1}. ${'A short paragraph keeps the story moving. ' * 20}',
          ),
      ],
    );
    final container = await support.openAtBoundary(
      tester,
      forward: true,
      platform: TargetPlatform.android,
      sourceBook: book,
    );
    final itemsPerChapter = book.chapters
        .map((chapter) => 1 + splitParagraphs(chapter.body).texts.length)
        .reduce((a, b) => a > b ? a : b);
    final gesture = await tester.startGesture(const Offset(195, 420));
    for (var frame = 0; frame < 400; frame++) {
      if (container.read(readerPositionProvider(book.id)).chapterIndex >= 20) {
        break;
      }
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      expect(
        tester
            .widget<ReaderScrollList>(find.byType(ReaderScrollList))
            .itemCount,
        lessThanOrEqualTo(10 * itemsPerChapter + 2),
      );
    }
    expect(
      container.read(readerPositionProvider(book.id)).chapterIndex,
      greaterThanOrEqualTo(20),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    final window = tester.widget<ScrollReader>(find.byType(ScrollReader)).book;
    expect(
      tester.widget<ReaderScrollList>(find.byType(ReaderScrollList)).itemCount,
      windowItemCount(window),
    );
    await support.unmount(tester);
  });
}
