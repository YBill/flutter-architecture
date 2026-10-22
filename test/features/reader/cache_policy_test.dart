import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/books/data/book_cache_io.dart';
import 'package:novelverse/features/books/data/book_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late DateTime now;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('novelverse-cache-');
    now = DateTime.utc(2026, 10, 22);
  });
  tearDown(() => directory.delete(recursive: true));

  test('byte budget evicts least recently used entries', () async {
    final cache = FileBookCache(
      directory: directory,
      maxBytes: 32,
      clock: () => now,
    );
    await cache.write('one', 'a' * 16);
    now = now.add(const Duration(seconds: 1));
    await cache.write('two', 'b' * 16);
    now = now.add(const Duration(seconds: 1));
    await cache.read('one');
    now = now.add(const Duration(seconds: 1));
    await cache.write('three', 'c' * 16);
    expect(await cache.read('two'), isNull);
    expect(await cache.read('one'), 'a' * 16);
    expect(await cache.read('three'), 'c' * 16);
  });

  test('entry budget and expiry survive a new cache instance', () async {
    final cache = FileBookCache(
      directory: directory,
      maxEntries: 1,
      clock: () => now,
    );
    await cache.write('one', 'first');
    now = now.add(const Duration(seconds: 1));
    await cache.write('two', 'second');
    expect(await cache.read('one'), isNull);
    now = now.add(const Duration(days: 31));
    final restarted = FileBookCache(directory: directory, clock: () => now);
    expect(await restarted.read('two'), isNull);
  });

  test(
    'environment caches are separate and long keys produce safe filenames',
    () async {
      final dev = FileBookCache(directory: directory, namespace: 'dev');
      final prod = FileBookCache(directory: directory, namespace: 'prod');
      final key = '../book/${'very-long-id' * 100}/chapter';
      await dev.write(key, 'dev text');
      expect(await prod.read(key), isNull);
      expect(await dev.read(key), 'dev text');
      final files = await Directory('${directory.path}/reader_books_v2_dev')
          .list()
          .toList();
      expect(files.single.uri.pathSegments.last.length, 69);
    },
  );

  test('OS cache removal is recovered on the next write', () async {
    final cache = FileBookCache(directory: directory);
    await cache.write('one', 'old');
    await Directory('${directory.path}/reader_books_v2_dev')
        .delete(recursive: true);
    await cache.write('two', 'new');
    expect(await cache.read('one'), isNull);
    expect(await cache.read('two'), 'new');
  });

  test(
    'detail first chapter seeds reader cache without another chapter request',
    () async {
      final requests = <String>[];
      final repository = BookRepository(
        api: MockBookApi(delay: Duration.zero, onRequest: requests.add),
        cache: MemoryBookCache(),
      );
      final detail = await repository.getDetail(sampleBookId);
      final catalog = await repository.getCatalog(detail);
      final chapter = await repository.getChapter(
        sampleBookId,
        catalog.chapters.first,
      );
      expect(chapter.body, detail.firstChapter?.body);
      expect(requests.where((path) => path.contains('/chapters/')), isEmpty);
    },
  );
}
