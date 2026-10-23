import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/logic/paragraph_splitter.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';

import 'helpers/mock_book_api.dart';
import 'helpers/reader_test_support.dart';

void main() {
  for (final atHeader in [true, false]) {
    testWidgets(
      'cached reopen at chapter ${atHeader ? 'title' : 'tail'} never activates a stale chapter',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 758);
        addTearDown(tester.view.reset);
        final api = MockBookApi();
        final catalog = await api.fetchCatalog(sampleBookId);
        final chapter = await api.fetchChapter(
          sampleBookId,
          catalog.chapters[5],
        );
        final offset = atHeader ? 0 : splitParagraphs(chapter.body).starts.last;
        final store = MemoryReadingProgressStore();
        store.values[sampleBookId] = ReaderPosition(
          chapterIndex: 5,
          charOffset: offset,
          chapterId: chapter.id,
          contentVersion: chapter.version,
        );
        final container = ProviderContainer(
          overrides: [
            ...readerTestOverrides(progressStore: store),
            bookApiProvider.overrideWithValue(api),
            bookCacheProvider.overrideWithValue(MemoryBookCache()),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(readerSettingsProvider.notifier)
            .update((s) => s.copyWith(mode: ReaderMode.scroll, fontSize: 18));
        final repository = container.read(bookRepositoryProvider);
        final detail = await repository.getDetail(sampleBookId);
        await repository.getCatalog(detail);
        for (final meta in catalog.chapters.skip(4).take(4)) {
          await repository.getChapter(sampleBookId, meta);
        }
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(navigatorKey: nav, home: const Scaffold()),
          ),
        );

        for (var reopen = 0; reopen < 3; reopen++) {
          var readable = false;
          final chapterChanges = <int>[];
          final subscription = container.listen(
            readerPositionProvider(sampleBookId),
            (_, next) {
              if (readable) chapterChanges.add(next.chapterIndex);
            },
          );
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const ReaderPage(bookId: sampleBookId),
            ),
          );
          var sawNextTitle = false;
          for (var frame = 0; frame < 30; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (find.byType(ScrollReader).evaluate().isEmpty) continue;
            readable = true;
            if (!atHeader) {
              final viewport = tester.getRect(find.byType(ScrollReader));
              final title = find.text(catalog.chapters[6].title);
              final nextTitleVisible = title.evaluate().any(
                (element) => tester
                    .getRect(find.byWidget(element.widget))
                    .overlaps(viewport),
              );
              if (sawNextTitle) {
                expect(
                  nextTitleVisible,
                  isTrue,
                  reason:
                      'Reopen $reopen frame $frame must not remove the prefetched title',
                );
              }
              sawNextTitle |= nextTitleVisible;
            }
          }
          expect(readable, isTrue);
          if (!atHeader) expect(sawNextTitle, isTrue);
          // Observe every notification: a wrong chapter can be written and
          // corrected in the same frame, while still scheduling window churn.
          expect(chapterChanges, everyElement(5));
          expect(
            container.read(readerPositionProvider(sampleBookId)).charOffset,
            offset,
          );
          subscription.close();
          nav.currentState!.pop();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
