import 'helpers/reader_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/reader/logic/paginator.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/reader/widgets/paged_reader.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';
import 'package:novelverse/features/reader/widgets/reader_scroll_list.dart';

void main() {
  testWidgets('正文和页码避开安全区，系统文字缩放不会改变分页测量', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final book = buildBook(
      id: 'safe-area',
      title: '安全区',
      chapters: [ChapterData(title: '第一章', body: '正文布局校验，要求正文完整并避开页脚。' * 300)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: readerTestOverrides(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.fromLTRB(16, 24, 12, 34),
                textScaler: const TextScaler.linear(2),
              ),
              child: PagedReader(book: book, onToggleMenu: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final body = find
        .byWidgetPredicate((w) => w is Text && (w.data?.length ?? 0) > 100)
        .first;
    final bodyRect = tester.getRect(body);
    expect(bodyRect.left, greaterThanOrEqualTo(16 + 22));
    expect(bodyRect.right, lessThanOrEqualTo(390 - 12 - 22));
    expect(bodyRect.bottom, lessThanOrEqualTo(750 - 34 - 36));
    final footer = find
        .byWidgetPredicate(
          (w) => w is Text && RegExp(r'^\d+/\d+$').hasMatch(w.data ?? ''),
        )
        .first;
    expect(tester.getRect(footer).bottom, lessThanOrEqualTo(750 - 34 - 10));
    expect(tester.getRect(footer).top, greaterThanOrEqualTo(bodyRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('超长章节标题在矮视口中仍可完整阅读', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 220));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final book = buildBook(
      id: 'long-title',
      title: '长标题',
      chapters: [ChapterData(title: '很长的章节标题' * 20, body: '正文不能丢失。')],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: readerTestOverrides(),
        child: MaterialApp(
          home: PagedReader(book: book, onToggleMenu: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(book.chapters.first.title), findsOneWidget);
    final vertical = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(vertical.scrollDirection, Axis.vertical);
    await tester.drag(find.byType(PageView), const Offset(-360, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('正文不能丢失'), findsOneWidget);
  });

  testWidgets('单换行长章节不会变成一个巨大的滚动 item', (tester) async {
    final book = buildBook(
      id: 'long-body',
      title: '长章',
      chapters: [
        ChapterData(
          title: '第一章',
          body: List.filled(500, '这是小说中的一段正文。' * 10).join('\n'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: readerTestOverrides(),
        child: MaterialApp(
          home: ScrollReader(book: book, onToggleMenu: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = tester.widget<ReaderScrollList>(find.byType(ReaderScrollList));
    expect(list.itemCount, greaterThan(100));
    list.itemScrollController.jumpTo(index: list.itemCount ~/ 2);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ScrollReader)),
    );
    expect(
      container.read(readerPositionProvider(book.id)).charOffset,
      greaterThan(book.chapters[0].body.length ~/ 3),
    );
    container
        .read(readerSettingsProvider.notifier)
        .update((s) => s.copyWith(fontSize: 28));
    await tester.pumpAndSettle();
    expect(
      container.read(readerPositionProvider(book.id)).charOffset,
      greaterThan(book.chapters[0].body.length ~/ 3),
    );
  });

  test('混合文字、长单词、emoji 的逐页渲染均不超过分页预算', () {
    final samples = [
      '　　中文与英文 Mixed content，标点和空白。\n\n' * 80,
      '👨‍👩‍👧‍👦🙂e\u0301𠮷\t a verylongwordwithoutspaces' * 80,
      'مرحبا بالعالم שלום עולם\n' * 80,
    ];
    for (final body in samples) {
      for (final fontSize in [14.0, 28.0]) {
        final style = ReaderSettings(
          fontSize: fontSize,
          lineHeight: 1.3,
          mode: ReaderMode.paged,
        ).textStyle;
        final breaks = Paginator.paginateChapter(
          body: body,
          style: style,
          maxWidth: 231,
          heightForPage: (_) => 170,
        );
        expect(breaks.first.start, 0);
        expect(breaks.last.end, body.length);
        for (var i = 0; i < breaks.length; i++) {
          if (i > 0) expect(breaks[i].start, breaks[i - 1].end);
          final painter = TextPainter(
            text: TextSpan(
              text: Paginator.pageText(body, breaks[i]),
              style: style,
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 231);
          expect(
            painter.height,
            lessThanOrEqualTo(170),
            reason: 'sample=${samples.indexOf(body)} font=$fontSize page=$i',
          );
          painter.dispose();
        }
      }
    }
  });
}
