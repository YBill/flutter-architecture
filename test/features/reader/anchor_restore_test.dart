import 'helpers/reader_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/app/app.dart';
import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/books/data/book_cache.dart';

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
    container
        .read(readerSettingsProvider.notifier)
        .update((s) => s.copyWith(fontSize: 24));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(firstLineAfterTurn),
      findsWidgets,
      reason: '翻页前的页首文字在改字号后仍应显示',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
