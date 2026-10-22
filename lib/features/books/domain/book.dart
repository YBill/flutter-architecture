class BookSummary {
  const BookSummary({
    required this.id,
    required this.title,
    required this.author,
    required this.chapterCount,
    this.coverUrl,
  });
  final String id;
  final String title;
  final String author;
  final String? coverUrl;
  final int chapterCount;
  factory BookSummary.fromJson(Map<String, dynamic> json) => BookSummary(
    id: json['id'] as String,
    title: json['title'] as String,
    author: json['author'] as String,
    coverUrl: json['coverUrl'] as String?,
    chapterCount: json['chapterCount'] as int,
  );
}

class BookDetail {
  const BookDetail({
    required this.summary,
    required this.description,
    required this.status,
    required this.category,
    required this.tags,
    required this.catalogVersion,
    this.firstChapter,
    this.readerCount = 0,
    this.savedCount = 0,
    this.rating = 0,
  });
  final BookSummary summary;
  final String description;
  final String status;
  final String category;
  final List<String> tags;
  final String catalogVersion;
  final Chapter? firstChapter;
  final int readerCount;
  final int savedCount;
  final double rating;
  factory BookDetail.fromJson(Map<String, dynamic> json) => BookDetail(
    summary: BookSummary.fromJson(json),
    description: json['description'] as String,
    status: json['status'] as String,
    category: json['category'] as String,
    tags: List<String>.from(json['tags'] as List),
    catalogVersion: json['catalogVersion'] as String,
    firstChapter: json['firstChapter'] == null
        ? null
        : Chapter.fromJson(
            Map<String, dynamic>.from(json['firstChapter'] as Map),
          ),
    readerCount: (json['readerCount'] as num?)?.toInt() ?? 0,
    savedCount: (json['savedCount'] as num?)?.toInt() ?? 0,
    rating: (json['rating'] as num?)?.toDouble() ?? 0,
  );
}

class BookRecommendation {
  const BookRecommendation({
    required this.book,
    required this.rating,
    required this.targetBookId,
  });

  final BookSummary book;
  final double rating;
  final String targetBookId;

  factory BookRecommendation.fromJson(Map<String, dynamic> json) =>
      BookRecommendation(
        book: BookSummary.fromJson(json),
        rating: (json['rating'] as num).toDouble(),
        targetBookId: json['targetBookId'] as String? ?? json['id'] as String,
      );
}

class ChapterMeta {
  const ChapterMeta({
    required this.id,
    required this.index,
    required this.title,
    required this.version,
  });
  final String id;

  /// 全书中从 0 开始的顺序，不是已加载列表的局部下标。
  final int index;
  final String title;
  final String version;
  factory ChapterMeta.fromJson(Map<String, dynamic> json) => ChapterMeta(
    id: json['id'] as String,
    index: json['index'] as int,
    title: json['title'] as String,
    version: json['version'] as String,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'title': title,
    'version': version,
  };
}

class BookCatalog {
  const BookCatalog({
    required this.bookId,
    required this.version,
    required this.chapters,
  });
  final String bookId;
  final String version;
  final List<ChapterMeta> chapters;
  factory BookCatalog.fromJson(Map<String, dynamic> json) => BookCatalog(
    bookId: json['bookId'] as String,
    version: json['version'] as String,
    chapters: (json['chapters'] as List)
        .map((e) => ChapterMeta.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'version': version,
    'chapters': chapters.map((c) => c.toJson()).toList(),
  };
}

/// 阅读器当前已加载的正文窗口；chapters 不要求包含全书。
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.chapters,
    this.totalChapters,
  });
  final String id;
  final String title;
  final List<Chapter> chapters;
  final int? totalChapters;
  int get chapterCount => totalChapters ?? chapters.length;
  int localIndex(int chapterIndex) =>
      chapters.indexWhere((c) => c.index == chapterIndex);
}

class Chapter {
  const Chapter({
    required this.index,
    required this.title,
    required this.body,
    this.id = '',
    this.version = '1',
  });
  final String id;
  final int index;
  final String title;
  final String body;
  final String version;
  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    id: json['id'] as String,
    index: json['index'] as int,
    title: json['title'] as String,
    body: json['body'] as String,
    version: json['version'] as String,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'title': title,
    'body': body,
    'version': version,
  };
}
