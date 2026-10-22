import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/book.dart';

const sampleBookId = 'claimed-ruthless-alpha';
const _assetRoot = 'assets/books/claimed_ruthless_alpha';

abstract class BookApi {
  Future<List<BookSummary>> fetchBooks();
  Future<BookDetail> fetchDetail(String bookId);
  Future<List<BookRecommendation>> fetchRecommendations(String bookId);
  Future<BookCatalog> fetchCatalog(String bookId);
  Future<Chapter> fetchChapter(String bookId, ChapterMeta chapter);
}

/// 模拟详情（内嵌完整第一章）、推荐、目录及单章正文接口。
/// 接真实服务端时替换此类，仓库、缓存和阅读器无需知道 asset 路径。
class MockBookApi implements BookApi {
  MockBookApi({
    this.delay = const Duration(milliseconds: 300),
    AssetBundle? bundle,
    this.onRequest,
  }) : _bundle = bundle ?? rootBundle;
  final Duration delay;
  final AssetBundle _bundle;
  final void Function(String path)? onRequest;
  Future<void> _request(String path) async {
    onRequest?.call(path);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  void _checkBook(String bookId) {
    if (bookId != sampleBookId) throw StateError('Book not found');
  }

  Future<Map<String, dynamic>> _json(String path) async =>
      jsonDecode(await _bundle.loadString(path, cache: false))
          as Map<String, dynamic>;
  @override
  Future<List<BookSummary>> fetchBooks() async {
    await _request('/books');
    final json = await _json('assets/books/books.json');
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
    final json = await _json('assets/books/recommendations.json');
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
    var body = await _bundle.loadString(
      '$_assetRoot/chapters/${int.parse(match[1]!)}.txt',
      cache: false,
    );
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
