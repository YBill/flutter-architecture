import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_providers.dart';
import '../data/chapter_bookmark_repository.dart';

final chapterBookmarkRepositoryProvider = Provider(
  (ref) => ChapterBookmarkRepository(ref.watch(appDatabaseProvider)),
);

final chapterBookmarksProvider = StreamProvider.autoDispose
    .family<Set<String>, String>(
      (ref, bookId) =>
          ref.watch(chapterBookmarkRepositoryProvider).watchChapterIds(bookId),
    );
