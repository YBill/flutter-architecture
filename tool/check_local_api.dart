import 'dart:io';

import 'package:dio/dio.dart';
import 'package:novelverse/core/network/api_client.dart';
import 'package:novelverse/features/books/data/http_book_api.dart';

/// Uses the app's real HTTP API and JSON models, without a Flutter UI.
Future<void> main(List<String> args) async {
  final baseUrl = args.isEmpty ? 'http://127.0.0.1:8787/api/v1/' : args.first;
  final dio = Dio(
    BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 5)),
  );
  final api = HttpBookApi(ApiClient(dio));
  try {
    final books = await api.fetchBooks();
    if (books.isEmpty) throw StateError('The server returned no books.');
    final id = books.first.id;
    final detail = await api.fetchDetail(id);
    final catalog = await api.fetchCatalog(id);
    final recommendations = await api.fetchRecommendations(id);
    if (catalog.chapters.isEmpty ||
        detail.firstChapter?.id != catalog.chapters.first.id) {
      throw StateError('The first chapter does not match the catalog.');
    }
    final index = catalog.chapters.length > 149
        ? 149
        : catalog.chapters.length - 1;
    final chapter = await api.fetchChapter(id, catalog.chapters[index]);
    if (chapter.id != catalog.chapters[index].id || chapter.body.isEmpty) {
      throw StateError('Unable to load the target chapter.');
    }
    stdout.writeln('HTTP API OK: ${detail.summary.title}');
    stdout.writeln(
      '${catalog.chapters.length} chapters; ${recommendations.length} recommendations; embedded first chapter: ${detail.firstChapter!.body.length} chars',
    );
    stdout.writeln(
      'Direct chapter ${index + 1}: ${chapter.id}, ${chapter.body.length} chars',
    );
  } finally {
    dio.close(force: true);
  }
}
