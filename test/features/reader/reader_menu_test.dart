import 'helpers/mock_book_api.dart';

import 'helpers/reader_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/books/data/book_cache.dart';

void main() {
  testWidgets('横屏打开Settings并切换行距时不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(750, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...readerTestOverrides(),
          bookCacheProvider.overrideWithValue(MemoryBookCache()),
          bookApiProvider.overrideWithValue(MockBookApi(delay: Duration.zero)),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: sampleBookId)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(375, 195));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Relaxed'));
    await tester.tap(find.text('Relaxed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
