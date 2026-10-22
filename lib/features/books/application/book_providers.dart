import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/providers/core_providers.dart';
import '../../reader/data/reading_progress_store.dart';
import '../data/book_api.dart';
import '../data/book_cache.dart';
import '../data/book_library_repository.dart';
import '../data/book_repository.dart';
import '../domain/book.dart';

final bookApiProvider = Provider<BookApi>((ref) {
  final logger = ref.watch(appLoggerProvider);
  return MockBookApi(onRequest: (path) => logger.debug('[Mock API] GET $path'));
});
final bookCacheProvider = Provider<BookCacheStore>(
  (ref) =>
      createBookCache(namespace: ref.watch(appConfigProvider).environment.name),
);
final bookRepositoryProvider = Provider(
  (ref) => BookRepository(
    api: ref.watch(bookApiProvider),
    cache: ref.watch(bookCacheProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);
final booksProvider = FutureProvider.autoDispose<List<BookSummary>>(
  (ref) => ref.watch(bookRepositoryProvider).getBooks(),
);
final bookDetailProvider = FutureProvider.autoDispose
    .family<BookDetail, String>(
      (ref, id) => ref.watch(bookRepositoryProvider).getDetail(id),
    );
final bookRecommendationsProvider = FutureProvider.autoDispose
    .family<List<BookRecommendation>, String>(
      (ref, id) => ref.watch(bookRepositoryProvider).getRecommendations(id),
    );
final bookCatalogProvider = FutureProvider.autoDispose
    .family<BookCatalog, String>((ref, id) async {
      final repository = ref.watch(bookRepositoryProvider);
      final detail = await ref.watch(bookDetailProvider(id).future);
      return repository.getCatalog(detail);
    });
final readingProgressStoreProvider = Provider<ReadingProgressStore>(
  (ref) => DriftReadingProgressStore(ref.watch(appDatabaseProvider)),
);
final bookLibraryRepositoryProvider = Provider(
  (ref) => BookLibraryRepository(ref.watch(appDatabaseProvider)),
);
final bookSavedProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, id) => ref.watch(bookLibraryRepositoryProvider).watchIsSaved(id),
);
