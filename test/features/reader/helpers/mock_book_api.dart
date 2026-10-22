import 'dart:convert';
import 'dart:io';

import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/books/domain/book.dart';

const _assetRoot = 'server/data/books/claimed_ruthless_alpha';

/// Test-only fixtures from the server data directory. Never bundled with the app.
class MockBookApi implements BookApi {
  MockBookApi({this.delay = Duration.zero, this.onRequest});
  final Duration delay;
  final void Function(String path)? onRequest;
  Future<void> _request(String path) async {
    onRequest?.call(path);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  void _checkBook(String bookId) {
    if (bookId != sampleBookId) throw StateError('Book not found');
  }

  Future<Map<String, dynamic>> _json(String path) async =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  @override
  Future<List<BookSummary>> fetchBooks() async {
    await _request('/books');
    final json = await _json('server/data/books/books.json');
    return (json['items'] as List)
        .map((e) => BookSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<BookDetail> fetchDetail(String bookId) async {
    await _request('/books/$bookId');
    _checkBook(bookId);
    final json = await _json('$_assetRoot/detail.json');
    final catalog = BookCatalog.fromJson(
      await _json('$_assetRoot/catalog.json'),
    );
    if (catalog.chapters.isNotEmpty) {
      json['firstChapter'] = (await _readChapter(catalog.chapters.first))
          .toJson();
    }
    return BookDetail.fromJson(json);
  }

  @override
  Future<List<BookRecommendation>> fetchRecommendations(String bookId) async {
    await _request('/books/$bookId/recommendations');
    _checkBook(bookId);
    final json = await _json('server/data/books/recommendations.json');
    return (json['items'] as List)
        .map(
          (item) => BookRecommendation.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  @override
  Future<BookCatalog> fetchCatalog(String bookId) async {
    await _request('/books/$bookId/chapters');
    _checkBook(bookId);
    return BookCatalog.fromJson(await _json('$_assetRoot/catalog.json'));
  }

  @override
  Future<Chapter> fetchChapter(String bookId, ChapterMeta chapter) async {
    await _request('/books/$bookId/chapters/${chapter.id}');
    _checkBook(bookId);
    return _readChapter(chapter);
  }

  Future<Chapter> _readChapter(ChapterMeta chapter) async {
    final match = RegExp(r'^alpha-(\d+)$').firstMatch(chapter.id);
    if (match == null) throw StateError('Chapter not found');
    var body = File('$_assetRoot/chapters/${int.parse(match[1]!)}.txt')
        .readAsStringSync();
    body = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // 原始文件保留不动。只移除与目录完全匹配的独立标题行；
    // 没有标题行的章节，绝不删除正文首行。
    final newline = body.indexOf('\n');
    if (newline >= 0 && body.substring(0, newline).trim() == chapter.title) {
      body = body.substring(newline + 1);
    }
    return Chapter(
      id: chapter.id,
      index: chapter.index,
      title: chapter.title,
      body: body.trim(),
      version: chapter.version,
    );
  }
}
