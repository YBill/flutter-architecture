import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'book_cache.dart';

BookCacheStore createBookCache({String namespace = 'dev'}) =>
    FileBookCache(namespace: namespace);

class _CacheEntry {
  _CacheEntry(this.size, this.accessedAt);
  final int size;
  DateTime accessedAt;
}

/// Re-downloadable text only. Durable progress lives separately in SQLite.
/// A lazy index avoids scanning thousands of files on every chapter request.
class FileBookCache implements BookCacheStore {
  FileBookCache({
    this.directory,
    this.namespace = 'dev',
    this.maxBytes = 50 * 1024 * 1024,
    this.maxEntries = 5000,
    this.maxAge = const Duration(days: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory? directory;
  final String namespace;
  final int maxBytes;
  final int maxEntries;
  final Duration maxAge;
  final DateTime Function() _clock;
  final _entries = <String, _CacheEntry>{};
  Future<Directory>? _root;
  Future<void> _pending = Future<void>.value();
  int _sequence = 0;

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  String _name(String key) => '${sha256.convert(utf8.encode(key))}.json';

  Future<Directory> _directory() async {
    if (_root != null) return _root!;
    final task = _initialize();
    _root = task;
    try {
      return await task;
    } catch (_) {
      _root = null;
      rethrow;
    }
  }

  Future<Directory> _initialize() async {
    final base = directory ?? await getApplicationCacheDirectory();
    final root = await Directory('${base.path}/reader_books_v2_$namespace')
        .create(recursive: true);
    _entries.clear();
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.tmp')) {
        await entity.delete();
      } else if (name.endsWith('.json')) {
        final stat = await entity.stat();
        _entries[name] = _CacheEntry(stat.size, stat.modified);
      }
    }
    await _trim(root);
    return root;
  }

  Future<void> _remove(Directory root, String name) async {
    _entries.remove(name);
    final file = File('${root.path}/$name');
    if (await file.exists()) await file.delete();
  }

  Future<void> _trim(Directory root) async {
    final now = _clock();
    final expired = _entries.entries
        .where((entry) => now.difference(entry.value.accessedAt) >= maxAge)
        .map((entry) => entry.key)
        .toList();
    for (final name in expired) {
      await _remove(root, name);
    }
    var size = _entries.values.fold<int>(0, (sum, entry) => sum + entry.size);
    if (size <= maxBytes && _entries.length <= maxEntries) return;
    final oldest = _entries.keys.toList()
      ..sort(
        (a, b) => _entries[a]!.accessedAt.compareTo(_entries[b]!.accessedAt),
      );
    for (final name in oldest) {
      if (size <= maxBytes && _entries.length <= maxEntries) break;
      size -= _entries[name]!.size;
      await _remove(root, name);
    }
  }

  @override
  Future<String?> read(String key) => _serial(() async {
    final root = await _directory();
    final name = _name(key);
    final file = File('${root.path}/$name');
    if (!await file.exists()) {
      _entries.remove(name);
      return null;
    }
    final entry =
        _entries[name] ??
        _CacheEntry(await file.length(), (await file.stat()).modified);
    if (_clock().difference(entry.accessedAt) >= maxAge) {
      await _remove(root, name);
      return null;
    }
    final value = await file.readAsString();
    entry.accessedAt = _clock();
    _entries[name] = entry;
    await file.setLastModified(entry.accessedAt);
    return value;
  });

  @override
  Future<void> write(String key, String value) => _serial(() async {
    final root = await _directory();
    if (!await root.exists()) {
      await root.create(recursive: true);
      _entries.clear();
    }
    final name = _name(key);
    final size = utf8.encode(value).length;
    if (size > maxBytes || maxEntries <= 0) {
      await _remove(root, name);
      return;
    }
    final file = File('${root.path}/$name');
    final temporary = File(
      '${file.path}.${_clock().microsecondsSinceEpoch}.${_sequence++}.tmp',
    );
    try {
      await temporary.writeAsString(value, flush: true);
      await temporary.rename(file.path);
      final accessedAt = _clock();
      await file.setLastModified(accessedAt);
      _entries[name] = _CacheEntry(size, accessedAt);
      await _trim(root);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  });
}
