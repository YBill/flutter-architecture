import 'helpers/reader_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/books/domain/book.dart';
import 'package:novelverse/features/reader/widgets/paged_reader.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';

void main() {
  final bookA = buildBook(
    id: 'a',
    title: '书A',
    chapters: const [ChapterData(title: '第一章', body: '甲书独有的正文段落。')],
  );
  final bookB = buildBook(
    id: 'b',
    title: '书B',
    chapters: const [ChapterData(title: '第一章', body: '乙书独有的正文段落。')],
  );

  testWidgets('换书后分页缓存失效，PagedReader 显示新书内容', (tester) async {
    Widget host(Book book) => ProviderScope(
      overrides: readerTestOverrides(),
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 700)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: PagedReader(book: book, onToggleMenu: () {}),
        ),
      ),
    );

    await tester.pumpWidget(host(bookA));
    await tester.pumpAndSettle();
    expect(find.textContaining('甲书独有'), findsWidgets);

    await tester.pumpWidget(host(bookB));
    await tester.pumpAndSettle();
    expect(find.textContaining('甲书独有'), findsNothing, reason: '不能沿用旧书分页');
    expect(find.textContaining('乙书独有'), findsWidgets);
  });

  testWidgets('换书后段落缓存失效，ScrollReader 显示新书内容', (tester) async {
    Widget host(Book book) => ProviderScope(
      // MaterialApp 提供 PageStorage（scrollable_positioned_list 需要）
      child: MaterialApp(
        home: SizedBox(
          width: 400,
          height: 700,
          child: ScrollReader(book: book, onToggleMenu: () {}),
        ),
      ),
    );

    await tester.pumpWidget(host(bookA));
    await tester.pumpAndSettle();
    expect(find.textContaining('甲书独有'), findsWidgets);

    await tester.pumpWidget(host(bookB));
    await tester.pumpAndSettle();
    expect(find.textContaining('甲书独有'), findsNothing, reason: '不能沿用旧书段落列表');
    expect(find.textContaining('乙书独有'), findsWidgets);
  });
}
