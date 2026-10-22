import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/books/domain/book.dart';

class TestBookApi implements BookApi {
  TestBookApi(this.book);
  final Book book;
  final requests = <int>[];
  int catalogRequests = 0;
  Future<void> Function(int index)? beforeChapter;
  final failures = <int>{};
  BookSummary get summary => BookSummary(
    id: book.id,
    title: book.title,
    author: 'Test Author',
    chapterCount: book.chapterCount,
  );
  @override
  Future<List<BookSummary>> fetchBooks() async => [summary];
  @override
  Future<List<BookRecommendation>> fetchRecommendations(String bookId) async =>
      [];
  @override
  Future<BookDetail> fetchDetail(String bookId) async => BookDetail(
    summary: summary,
    description: 'A test book.',
    status: 'Completed',
    category: 'Fiction',
    tags: [],
    catalogVersion: 'catalog-v1',
  );
  @override
  Future<BookCatalog> fetchCatalog(String bookId) async {
    catalogRequests++;
    return BookCatalog(
      bookId: book.id,
      version: 'catalog-v1',
      chapters: [
        for (final c in book.chapters)
          ChapterMeta(
            id: c.id,
            index: c.index,
            title: c.title,
            version: c.version,
          ),
      ],
    );
  }

  @override
  Future<Chapter> fetchChapter(String bookId, ChapterMeta chapter) async {
    requests.add(chapter.index);
    if (beforeChapter != null) await beforeChapter!(chapter.index);
    if (failures.contains(chapter.index)) {
      throw StateError('Simulated chapter failure');
    }
    return book.chapters.firstWhere((c) => c.id == chapter.id);
  }
}
