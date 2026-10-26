import 'dart:convert';

import '../../../core/logging/app_logger.dart';

import '../domain/book.dart';
import 'book_api.dart';
import 'book_cache.dart';

class BookRepository {
  BookRepository({
    required this.api,
    required this.cache,
    this.memoryLimit = 10,
    this.memoryByteLimit = 1024 * 1024,
    this.logger,
  });
  final BookApi api;
  final BookCacheStore cache;
  final int memoryLimit;
  final int memoryByteLimit;
  final AppLogger? logger;
  final _pending = <String, Future<Object>>{};
  final _catalogs = <String, BookCatalog>{};
  final _chapters = <String, Chapter>{};

  Future<T> _once<T extends Object>(String key, Future<T> Function() action) {
    final existing = _pending[key];
    if (existing != null) return existing.then((value) => value as T);
    final future = Future<T>.sync(action).whenComplete(() {
      _pending.remove(key);
    });
    _pending[key] = future;
    return future;
  }

  Future<List<BookSummary>> getBooks() => _once('books', api.fetchBooks);
  Future<BookDetail> getDetail(String id) => _once('detail/$id', () async {
    final detail = await api.fetchDetail(id);
    final first = detail.firstChapter;
    if (first != null && first.index == 0 && first.id.isNotEmpty) {
      final key = 'chapter/$id/${first.id}/${first.version}';
      _remember(key, first);
      await _write(key, first.toJson());
    }
    return detail;
  });

  Future<List<BookRecommendation>> getRecommendations(String id) =>
      _once('recommendations/$id', () => api.fetchRecommendations(id));

  void _remember(String key, Chapter chapter) {
    _chapters.remove(key);
    _chapters[key] = chapter;
    while (_chapters.length > memoryLimit ||
        _chapters.values.fold<int>(
              0,
              (sum, item) => sum + item.body.length * 2,
            ) >
            memoryByteLimit) {
      _chapters.remove(_chapters.keys.first);
    }
  }

  Future<Map<String, dynamic>?> _read(String key) async {
    try {
      final value = await cache.read(key);
      if (value != null) return jsonDecode(value) as Map<String, dynamic>;
    } catch (_) {
      /* Missing or invalid cache is fetched again. */
    }
    return null;
  }

  Future<void> _write(String key, Map<String, dynamic> value) async {
    try {
      await cache.write(key, jsonEncode(value));
    } catch (_) {
      /* Cache failure must not hide successfully fetched text. */
    }
  }

  Future<BookCatalog> getCatalog(BookDetail detail) async {
    final id = detail.summary.id;
    final key = 'catalog/$id/${detail.catalogVersion}';
    final memory = _catalogs.remove(key);
    if (memory != null) {
      _catalogs[key] = memory;
      return memory;
    }
    return _once(key, () async {
      final stored = await _read(key);
      BookCatalog? catalog;
      try {
        if (stored != null) catalog = BookCatalog.fromJson(stored);
      } catch (_) {
        /* Invalid cache is fetched again. */
      }
      if (catalog?.bookId != id || catalog?.version != detail.catalogVersion) {
        catalog = await api.fetchCatalog(id);
        if (catalog.bookId != id || catalog.version != detail.catalogVersion) {
          throw StateError('Catalog version changed. Please refresh the book.');
        }
        await _write(key, catalog.toJson());
      } else {
        logger?.debug('[Book cache] disk $key');
      }
      _catalogs[key] = catalog!;
      while (_catalogs.length > 3) {
        _catalogs.remove(_catalogs.keys.first);
      }
      return catalog;
    });
  }

  /// Synchronous lookup for composing a complete reader window before paint.
  /// A miss never starts file I/O or a network request.
  Chapter? getMemoryChapter(String bookId, ChapterMeta meta) {
    final key = 'chapter/$bookId/${meta.id}/${meta.version}';
    final cached = _chapters.remove(key);
    if (cached != null &&
        cached.index == meta.index &&
        cached.title == meta.title) {
      _chapters[key] = cached;
      logger?.debug('[Book cache] memory $key');
      return cached;
    }
    return null;
  }

  Future<Chapter> getChapter(String bookId, ChapterMeta meta) async {
    final cached = getMemoryChapter(bookId, meta);
    if (cached != null) return cached;
    final key = 'chapter/$bookId/${meta.id}/${meta.version}';
    return _once(key, () async {
      final stored = await _read(key);
      Chapter? chapter;
      try {
        if (stored != null) chapter = Chapter.fromJson(stored);
      } catch (_) {
        /* Invalid cache is fetched again. */
      }
      if (chapter?.id != meta.id ||
          chapter?.version != meta.version ||
          chapter?.index != meta.index ||
          chapter?.title != meta.title) {
        chapter = await api.fetchChapter(bookId, meta);
        if (chapter.id != meta.id ||
            chapter.version != meta.version ||
            chapter.index != meta.index) {
          throw StateError('Chapter version changed. Please refresh the book.');
        }
        await _write(key, chapter.toJson());
      } else {
        logger?.debug('[Book cache] disk $key');
      }
      _remember(key, chapter!);
      return chapter;
    });
  }
}

/// 已切章文本的纯构造工具，用于导入和排版测试，不发起任何加载。
class ChapterData {
  const ChapterData({required this.title, required this.body});
  final String title;
  final String body;
}

Book buildBook({
  required String id,
  required String title,
  required List<ChapterData> chapters,
}) => Book(
  id: id,
  title: title,
  chapters: [
    for (var i = 0; i < chapters.length; i++)
      Chapter(
        id: '$id-$i',
        index: i,
        title: chapters[i].title.trim().isEmpty
            ? 'Chapter ${i + 1}'
            : chapters[i].title.trim(),
        body: chapters[i].body
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .trim(),
      ),
  ],
);
