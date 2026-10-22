import '../../../core/network/api_client.dart';
import '../domain/book.dart';
import 'book_api.dart';

/// HTTP implementation shared by the local server and the future backend.
class HttpBookApi implements BookApi {
  HttpBookApi(this._client);

  final ApiClient _client;

  String _bookPath(String id) => 'books/${Uri.encodeComponent(id)}';

  @override
  Future<List<BookSummary>> fetchBooks() => _client.get(
    'books',
    decode: (data) => _items(data, BookSummary.fromJson),
  );

  @override
  Future<BookDetail> fetchDetail(String bookId) => _client.get(
    _bookPath(bookId),
    decode: (data) => BookDetail.fromJson(_json(data)),
  );

  @override
  Future<List<BookRecommendation>> fetchRecommendations(String bookId) =>
      _client.get(
        '${_bookPath(bookId)}/recommendations',
        decode: (data) => _items(data, BookRecommendation.fromJson),
      );

  @override
  Future<BookCatalog> fetchCatalog(String bookId) => _client.get(
    '${_bookPath(bookId)}/chapters',
    decode: (data) => BookCatalog.fromJson(_json(data)),
  );

  @override
  Future<Chapter> fetchChapter(String bookId, ChapterMeta chapter) =>
      _client.get(
        '${_bookPath(bookId)}/chapters/${Uri.encodeComponent(chapter.id)}',
        decode: (data) => Chapter.fromJson(_json(data)),
      );

  Map<String, dynamic> _json(Object? data) =>
      Map<String, dynamic>.from(data as Map);

  List<T> _items<T>(Object? data, T Function(Map<String, dynamic>) decode) =>
      (_json(data)['items'] as List)
          .map((item) => decode(_json(item)))
          .toList();
}
