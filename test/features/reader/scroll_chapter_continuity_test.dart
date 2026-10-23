import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/logic/paragraph_splitter.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';

import 'helpers/reader_test_support.dart';
import 'helpers/test_book_api.dart';

Book continuityBook() => buildBook(
  id: 'chapter-continuity',
  title: 'Continuous Reading',
  chapters: [
    for (var chapter = 1; chapter <= 20; chapter++)
      ChapterData(
        title: 'Chapter $chapter',
        body: [
          for (var paragraph = 0; paragraph < 20; paragraph++)
            'Chapter $chapter paragraph $paragraph. '
                '${'The path continues through the forest without stopping. ' * 4}',
        ].join('\n\n'),
      ),
  ],
);

Future<ProviderContainer> openAtBoundary(
  WidgetTester tester, {
  required bool forward,
  required TargetPlatform platform,
  Book? sourceBook,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final book = sourceBook ?? continuityBook();
  final chapter = book.chapters[forward ? 8 : 9];
  final paragraphs = splitParagraphs(chapter.body);
  final progress = MemoryReadingProgressStore();
  progress.values[book.id] = ReaderPosition(
    chapterIndex: chapter.index,
    chapterId: chapter.id,
    contentVersion: chapter.version,
    charOffset:
        paragraphs.starts[(forward ? paragraphs.starts.length - 2 : 1).clamp(
          0,
          paragraphs.starts.length - 1,
        )],
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
      .update((s) => s.copyWith(mode: ReaderMode.scroll));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: ReaderPage(bookId: book.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

ScrollPosition scrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ScrollReader),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final forward in [true, false]) {
      final name = '${platform.name}: ${forward ? '9 to 10' : '10 to 9'}';
      final delta = forward ? -80.0 : 80.0;
      final target = forward ? 9 : 8;
      testWidgets(
        '$name: one held drag continues across the chapter boundary',
        (tester) async {
          final container = await openAtBoundary(
            tester,
            forward: forward,
            platform: platform,
          );
          final position = scrollPosition(tester);
          final gesture = await tester.startGesture(const Offset(195, 420));
          for (var step = 0; step < 30; step++) {
            await gesture.moveBy(Offset(0, delta));
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
          expect(scrollPosition(tester), same(position));
          final before = position.pixels;
          await gesture.moveBy(Offset(0, delta));
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(position.pixels - before, closeTo(-delta, 1));
          // Keep the very same pointer down through two more window changes.
          final furtherTarget = target + (forward ? 2 : -2);
          for (var step = 0; step < 240; step++) {
            if (container
                    .read(readerPositionProvider('chapter-continuity'))
                    .chapterIndex ==
                furtherTarget) {
              break;
            }
            await gesture.moveBy(Offset(0, delta * 2));
            await tester.pump(const Duration(milliseconds: 16));
            await tester.pump();
          }
          expect(
            container
                .read(readerPositionProvider('chapter-continuity'))
                .chapterIndex,
            furtherTarget,
          );
          expect(scrollPosition(tester), same(position));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ScrollReader>(find.byType(ScrollReader))
                .book
                .chapters,
            hasLength(3),
          );
          expect(tester.takeException(), isNull);
          await unmount(tester);
        },
      );

      testWidgets('$name: a fling keeps moving after the window changes', (
        tester,
      ) async {
        final container = await openAtBoundary(
          tester,
          forward: forward,
          platform: platform,
        );
        final position = scrollPosition(tester);
        await tester.fling(find.byType(ScrollReader), Offset(0, delta), 2200);
        for (var frame = 0; frame < 50; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
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
        expect(scrollPosition(tester), same(position));
        expect(position.isScrollingNotifier.value, isTrue);
        expect(
          tester
              .widget<ScrollReader>(find.byType(ScrollReader))
              .book
              .chapters
              .map((c) => c.index),
          [target - 1, target, target + 1],
        );
        final viewport = tester.getRect(find.byType(ScrollReader));
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .firstWhere(
              (text) =>
                  (text.data?.length ?? 0) > 50 &&
                  text.data!.startsWith('Chapter ') &&
                  tester.getRect(find.byWidget(text)).overlaps(viewport),
            )
            .data!;
        final anchor = find.text(text);
        final before = tester.getTopLeft(anchor).dy;
        await tester.pump(const Duration(milliseconds: 32));
        expect(
          (tester.getTopLeft(anchor).dy - before) * delta.sign,
          greaterThan(5),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }
  }
}
