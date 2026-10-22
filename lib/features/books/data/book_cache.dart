import 'book_cache_stub.dart'
    if (dart.library.io) 'book_cache_io.dart'
    as platform;

abstract class BookCacheStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryBookCache implements BookCacheStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

BookCacheStore createBookCache({String namespace = 'dev'}) =>
    platform.createBookCache(namespace: namespace);
