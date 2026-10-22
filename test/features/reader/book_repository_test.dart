import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/books/data/book_cache_io.dart';
import 'package:novelverse/features/books/data/book_repository.dart';
import 'package:novelverse/features/books/domain/book.dart';

import 'helpers/test_book_api.dart';

void main() {
  final book = buildBook(
    id: 'cached',
    title: 'Cached book',
    chapters: const [
      ChapterData(title: 'One', body: 'First chapter.'),
      ChapterData(title: 'Two', body: 'Second chapter.'),
    ],
  );

  test(
    'concurrent requests share one fetch; memory eviction reuses disk cache',
    () async {
      final api = TestBookApi(book);
      final cache = MemoryBookCache();
      final repository = BookRepository(api: api, cache: cache, memoryLimit: 1);
      final catalog = await repository.getCatalog(
        await repository.getDetail(book.id),
      );
      final gate = Completer<void>();
      api.beforeChapter = (_) => gate.future;
      final first = repository.getChapter(book.id, catalog.chapters.first);
      final second = repository.getChapter(book.id, catalog.chapters.first);
      await Future<void>.delayed(Duration.zero);
      expect(api.requests, [0]);
      gate.complete();
      expect(await first, same(await second));
      await repository.getChapter(book.id, catalog.chapters.last);
      final reread = await repository.getChapter(
        book.id,
        catalog.chapters.first,
      );
      expect(reread.body, 'First chapter.');
      expect(api.requests, [0, 1]);
    },
  );

  test('new repository process reuses catalog and chapter files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reader-cache-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cache = FileBookCache(directory: directory);
    final api = TestBookApi(book);
    final first = BookRepository(api: api, cache: cache);
    final detail = await first.getDetail(book.id);
    final catalog = await first.getCatalog(detail);
    await first.getChapter(book.id, catalog.chapters.first);
    final newApi = TestBookApi(book)..failures.add(0);
    final second = BookRepository(
      api: newApi,
      cache: FileBookCache(directory: directory),
    );
    final cachedCatalog = await second.getCatalog(detail);
    expect(cachedCatalog.chapters.length, 2);
    expect(
      (await second.getChapter(book.id, cachedCatalog.chapters.first)).body,
      'First chapter.',
    );
    expect(newApi.requests, isEmpty);
    expect(newApi.catalogRequests, 0);
  });

  test(
    'changed content version fetches new text instead of stale cache',
    () async {
      final cache = MemoryBookCache();
      final first = BookRepository(api: TestBookApi(book), cache: cache);
      final catalog = await first.getCatalog(await first.getDetail(book.id));
      await first.getChapter(book.id, catalog.chapters.first);
      final changed = Book(
        id: book.id,
        title: book.title,
        chapters: [
          Chapter(
            id: book.chapters.first.id,
            index: 0,
            title: 'One',
            body: 'Updated chapter.',
            version: 'v2',
          ),
        ],
      );
      final newApi = TestBookApi(changed);
      final next = BookRepository(api: newApi, cache: cache);
      final chapter = await next.getChapter(
        book.id,
        ChapterMeta(
          id: changed.chapters.first.id,
          index: 0,
          title: 'One',
          version: 'v2',
        ),
      );
      expect(chapter.body, 'Updated chapter.');
      expect(newApi.requests, [0]);
    },
  );

  test(
    'failed requests can be retried and are never cached as empty chapters',
    () async {
      final api = TestBookApi(book)..failures.add(0);
      final repository = BookRepository(api: api, cache: MemoryBookCache());
      final catalog = await repository.getCatalog(
        await repository.getDetail(book.id),
      );
      await expectLater(
        repository.getChapter(book.id, catalog.chapters.first),
        throwsStateError,
      );
      api.failures.clear();
      expect(
        (await repository.getChapter(book.id, catalog.chapters.first)).body,
        'First chapter.',
      );
      expect(api.requests, [0, 0]);
    },
  );
}
