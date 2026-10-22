import 'helpers/reader_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_repository.dart';

import 'helpers/test_book_api.dart';

import 'package:novelverse/features/books/data/book_cache.dart';

import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets('深处位置切换模式、改字号和旋转窗口后仍保留附近内容', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final book = buildBook(
      id: 'round-trip',
      title: '定位测试',
      chapters: [
        ChapterData(
          title: '第一章',
          body: List.generate(
            100,
            (i) => List.generate(15, (j) => '第$i段第$j句，连续小说正文，包含足够多的文字。').join(),
          ).join('\n\n'),
        ),
      ],
    );
    final initialOffset = book.chapters.first.body.length ~/ 2;
    final container = ProviderContainer(
      overrides: [
        ...readerTestOverrides(),
        bookApiProvider.overrideWithValue(TestBookApi(book)),
        bookCacheProvider.overrideWithValue(MemoryBookCache()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(readerPositionProvider(book.id).notifier)
        .update(0, initialOffset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReaderPage(bookId: book.id)),
      ),
    );
    await tester.pumpAndSettle();
    void expectNearbyContent() {
      final viewport = tester.getRect(find.byType(Scaffold));
      final visibleBodies = find
          .byWidgetPredicate((w) => w is Text && (w.data?.length ?? 0) > 50)
          .evaluate()
          .where((element) {
            return viewport.overlaps(
              tester.getRect(find.byWidget(element.widget)),
            );
          });
      expect(visibleBodies, isNotEmpty);
      expect(
        visibleBodies.any((element) {
          final text = (element.widget as Text).data!;
          final start = book.chapters.first.body.indexOf(text);
          return start >= 0 &&
              start <= initialOffset + 200 &&
              start + text.length >= initialOffset - 200;
        }),
        isTrue,
        reason: '实际可见正文也必须包含锚点附近的文字，不能仅检查保存的坐标',
      );
    }

    expectNearbyContent();
    for (var i = 0; i < 3; i++) {
      container
          .read(readerSettingsProvider.notifier)
          .update((s) => s.copyWith(mode: ReaderMode.scroll));
      await tester.pumpAndSettle();
      final offset = container.read(readerPositionProvider(book.id)).charOffset;
      expect((offset - initialOffset).abs(), lessThanOrEqualTo(200));
      expectNearbyContent();
      container
          .read(readerSettingsProvider.notifier)
          .update((s) => s.copyWith(mode: ReaderMode.paged));
      await tester.pumpAndSettle();
      expect(
        (container.read(readerPositionProvider(book.id)).charOffset -
                initialOffset)
            .abs(),
        lessThanOrEqualTo(200),
      );
    }

    expectNearbyContent();
    // 重排后旧页码可能已越界，仍应按文字位置恢复。
    for (final size in [28.0, 14.0]) {
      container
          .read(readerSettingsProvider.notifier)
          .update((s) => s.copyWith(fontSize: size));
      await tester.pumpAndSettle();
      expect(
        (container.read(readerPositionProvider(book.id)).charOffset -
                initialOffset)
            .abs(),
        lessThanOrEqualTo(200),
      );
      expect(tester.takeException(), isNull);
      expectNearbyContent();
    }
    await tester.binding.setSurfaceSize(const Size(750, 390));
    await tester.pumpAndSettle();
    expect(
      (container.read(readerPositionProvider(book.id)).charOffset -
              initialOffset)
          .abs(),
      lessThanOrEqualTo(200),
    );
    expect(tester.takeException(), isNull);

    expectNearbyContent();
    container
        .read(readerSettingsProvider.notifier)
        .update((s) => s.copyWith(mode: ReaderMode.scroll));
    await tester.pumpAndSettle();
    final list = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    // 不等待 ScrollEnd，视口位置变化时就应更新锚点。
    list.itemScrollController!.jumpTo(index: list.itemCount * 3 ~/ 4);
    await tester.pump();
    await tester.pump();
    expect(
      container.read(readerPositionProvider(book.id)).charOffset,
      greaterThan(initialOffset + 1000),
    );
    expect(find.byType(ScrollReader), findsOneWidget);
  });
}
