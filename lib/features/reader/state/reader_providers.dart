import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';
import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../../../core/storage/preferences_store.dart';
import '../data/reading_progress_store.dart';
import '../domain/reading_position.dart';

export '../../books/application/book_providers.dart';
export '../domain/reading_position.dart';
import '../../books/domain/book.dart';
import '../domain/reader_settings.dart';

/// 全局阅读设置（字号/行距/模式）
class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  PreferencesStore? _store;
  AppLogger? _logger;
  bool _edited = false;
  Future<void> _writes = Future<void>.value();

  Future<void> initialize(PreferencesStore store, AppLogger logger) async {
    if (_store != null) return;
    _store = store;
    _logger = logger;
    try {
      final value = await store.getString('reader_settings');
      if (value != null && !_edited && ref.mounted) {
        final json = jsonDecode(value) as Map<String, dynamic>;
        state = ReaderSettings(
          fontSize: ((json['fontSize'] as num?)?.toDouble() ?? 18).clamp(
            14,
            28,
          ),
          lineHeight: ((json['lineHeight'] as num?)?.toDouble() ?? 1.45).clamp(
            1.3,
            1.6,
          ),
          mode: ReaderMode.values.byName(json['mode'] as String? ?? 'paged'),
          isNightMode: json['isNightMode'] as bool? ?? false,
        );
      }
    } catch (error, stack) {
      logger.error(
        'Could not restore reader settings.',
        error: error,
        stackTrace: stack,
      );
    }
  }

  @override
  ReaderSettings build() {
    return const ReaderSettings(
      fontSize: 18,
      lineHeight: 1.45,
      mode: ReaderMode.paged,
    );
  }

  void update(ReaderSettings Function(ReaderSettings) reducer) {
    _edited = true;
    state = reducer(state);
    final settings = state;
    final store = _store;
    if (store != null) {
      _writes = _writes
          .then(
            (_) => store.setString(
              'reader_settings',
              jsonEncode({
                'fontSize': settings.fontSize,
                'lineHeight': settings.lineHeight,
                'mode': settings.mode.name,
                'isNightMode': settings.isNightMode,
              }),
            ),
          )
          .catchError((Object error, StackTrace stack) {
            _logger?.error(
              'Could not save reader settings.',
              error: error,
              stackTrace: stack,
            );
          });
    }
  }
}

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
    );

/// In-memory position stays synchronous for pagination and scroll callbacks.
/// Only visible, loaded chapters may replace the durable database position.
class ReaderPositionNotifier extends Notifier<ReaderPosition> {
  ReaderPositionNotifier(this.bookId);
  final String bookId;
  ReadingProgressStore? _store;
  BookCatalog? _catalog;
  final _available = <int, Chapter>{};
  ReaderPosition _latest = const ReaderPosition(chapterIndex: 0, charOffset: 0);
  ReaderPosition? _lastSaved;
  Future<void>? _restoring;
  Future<void> _pending = Future<void>.value();
  Timer? _timer;
  bool _edited = false;
  void Function(Object, StackTrace)? _reportError;

  @override
  ReaderPosition build() {
    ref.onDispose(() {
      _timer?.cancel();
      unawaited(flush().catchError(_report));
    });
    return _latest;
  }

  Future<void> restore(
    ReadingProgressStore store, {
    void Function(Object, StackTrace)? onError,
  }) {
    _store = store;
    _reportError = onError;
    return _restoring ??= _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await _store!.read(bookId);
      if (ref.mounted && !_edited && saved != null) {
        _lastSaved = saved;
        state = _latest = saved;
      }
    } catch (_) {
      _restoring = null;
      rethrow;
    }
  }

  void bindCatalog(BookCatalog catalog) {
    _catalog = catalog;
    _available.clear();
    if (catalog.chapters.isEmpty) return;
    final saved = _latest;
    final byId = saved.chapterId == null
        ? -1
        : catalog.chapters.indexWhere(
            (chapter) => chapter.id == saved.chapterId,
          );
    final index = byId >= 0
        ? byId
        : saved.chapterIndex.clamp(0, catalog.chapters.length - 1);
    final meta = catalog.chapters[index];
    final changed =
        saved.chapterId != null &&
        (byId < 0 ||
            (saved.contentVersion != null &&
                saved.contentVersion != meta.version));
    state = _latest = ReaderPosition(
      chapterIndex: index,
      charOffset: changed ? 0 : saved.charOffset,
      chapterId: meta.id,
      contentVersion: meta.version,
    );
  }

  void registerChapter(Chapter chapter) {
    _available.remove(chapter.index);
    _available[chapter.index] = chapter;
    while (_available.length > 10) {
      _available.remove(_available.keys.first);
    }
    if (chapter.index == _latest.chapterIndex) _schedule();
  }

  void update(int chapterIndex, int charOffset) {
    _edited = true;
    final catalog = _catalog;
    final meta =
        catalog != null &&
            chapterIndex >= 0 &&
            chapterIndex < catalog.chapters.length
        ? catalog.chapters[chapterIndex]
        : null;
    final next = ReaderPosition(
      chapterIndex: chapterIndex,
      charOffset: charOffset.clamp(0, 1 << 30),
      chapterId: meta?.id,
      contentVersion: meta?.version,
    );
    if (!_same(state, next)) state = next;
    _latest = next;
    _schedule();
  }

  bool _same(ReaderPosition? a, ReaderPosition b) =>
      a?.chapterIndex == b.chapterIndex &&
      a?.charOffset == b.charOffset &&
      a?.chapterId == b.chapterId &&
      a?.contentVersion == b.contentVersion;

  void _schedule() {
    if (_store == null || !_available.containsKey(_latest.chapterIndex)) return;
    // Throttle rather than debounce: continuous scrolling still saves every 500ms.
    _timer ??= Timer(const Duration(milliseconds: 500), () {
      _timer = null;
      unawaited(flush().catchError(_report));
    });
  }

  void _report(Object error, StackTrace stack) =>
      _reportError?.call(error, stack);

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final store = _store;
    final current = _latest;
    final chapter = _available[current.chapterIndex];
    if (store == null ||
        chapter == null ||
        current.chapterId == null ||
        current.contentVersion == null ||
        chapter.version != current.contentVersion) {
      return _pending;
    }
    final snapshot = ReaderPosition(
      chapterIndex: current.chapterIndex,
      chapterId: current.chapterId,
      contentVersion: current.contentVersion,
      charOffset: current.charOffset.clamp(0, chapter.body.length),
    );
    final operation = _pending.then((_) async {
      if (_same(_lastSaved, snapshot)) return;
      await store.write(bookId, snapshot);
      _lastSaved = snapshot;
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }
}

final readerPositionProvider = NotifierProvider.autoDispose
    .family<ReaderPositionNotifier, ReaderPosition, String>(
      ReaderPositionNotifier.new,
    );

/// 外部跳章请求（目录/上一章/下一章）。seq 防止同一次请求被重复处理。
class JumpRequest {
  const JumpRequest({
    required this.chapterIndex,
    required this.seq,
    this.fromEnd = false,
  });

  final int chapterIndex;
  final int seq;
  final bool fromEnd;
}

class ReaderJumpNotifier extends Notifier<JumpRequest?> {
  ReaderJumpNotifier(this.bookId);
  final String bookId;
  @override
  JumpRequest? build() => null;

  void jumpToChapter(int chapterIndex, {bool fromEnd = false}) {
    state = JumpRequest(
      chapterIndex: chapterIndex,
      seq: (state?.seq ?? 0) + 1,
      fromEnd: fromEnd,
    );
  }
}

final readerJumpProvider =
    NotifierProvider.family<ReaderJumpNotifier, JumpRequest?, String>(
      ReaderJumpNotifier.new,
    );
