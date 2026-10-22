import 'helpers/mock_book_api.dart';

import 'helpers/reader_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/app/app.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/books/data/book_api.dart';

// 单独成文件：Riverpod FutureProvider 在测试间会残留调度帧，
// 同文件多个 testWidgets 时 pumpAndSettle 互相干扰。

void main() {
  testWidgets('改字号后仍停留在原文字位置（锚点恢复）', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...readerTestOverrides(),
          bookCacheProvider.overrideWithValue(MemoryBookCache()),
          bookApiProvider.overrideWithValue(MockBookApi(delay: Duration.zero)),
        ],
        child: const NovelverseApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-reading')));
    await tester.pumpAndSettle();

    String currentBodyText() => tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (w) => w is Text && (w.data?.length ?? 0) > 20,
          ),
        )
        .first
        .data!;

    final firstLineBefore = currentBodyText().split('\n').first;

    // 右区点按翻到下一页
    await tester.tapAt(const Offset(700, 400));
    await tester.pumpAndSettle();
    final firstLineAfterTurn = currentBodyText().split('\n').first;
    expect(firstLineAfterTurn, isNot(firstLineBefore));

    // 改字号触发重排，必须回到同一文字位置，而不是保留旧页码
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelverseApp)),
    );
    final anchor = container
        .read(readerPositionProvider(sampleBookId))
        .charOffset;
    final chapterBody = container
        .read(bookDetailProvider(sampleBookId))
        .requireValue
        .firstChapter!
        .body;
    container
        .read(readerSettingsProvider.notifier)
        .update((s) => s.copyWith(fontSize: 24));
    await tester.pumpAndSettle();

    // A long paragraph may span the new page boundary. The original character
    // must remain inside the displayed page, rather than requiring the whole
    // previous paragraph to fit at the larger font size.
    final displayed = currentBodyText();
    final start = chapterBody.indexOf(displayed);
    expect(start, greaterThanOrEqualTo(0));
    expect(start, lessThanOrEqualTo(anchor));
    expect(start + displayed.length, greaterThan(anchor));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
