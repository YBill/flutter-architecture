import 'book_cache.dart';

BookCacheStore createBookCache({String namespace = 'dev'}) => MemoryBookCache();
