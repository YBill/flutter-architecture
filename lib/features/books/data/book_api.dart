import '../domain/book.dart';

const sampleBookId = 'claimed-ruthless-alpha';

abstract class BookApi {
  Future<List<BookSummary>> fetchBooks();
  Future<BookDetail> fetchDetail(String bookId);
  Future<List<BookRecommendation>> fetchRecommendations(String bookId);
  Future<BookCatalog> fetchCatalog(String bookId);
  Future<Chapter> fetchChapter(String bookId, ChapterMeta chapter);
}
