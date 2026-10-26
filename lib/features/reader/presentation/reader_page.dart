import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';

import '../../books/domain/book.dart';
import '../domain/reader_settings.dart';
import '../state/reader_providers.dart';
import '../state/reader_brightness_provider.dart';
import '../widgets/paged_reader.dart';
import '../widgets/reader_menu.dart';
import '../widgets/reader_theme.dart';
import '../widgets/scroll_reader.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.bookId, this.initialChapterId});
  final String bookId;
  final String? initialChapterId;
  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  late ReaderPositionNotifier _position;
  bool _menuVisible = false;
  BookDetail? _detail;
  BookCatalog? _catalog;
  Object? _openError;
  int _targetIndex = 0;
  int _epoch = 0;
  final _loaded = <int, Chapter>{};
  final _loading = <int, Future<void>>{};
  final _errors = <int, Object>{};
  Book? _window;
  // Chapter activation and prefetch update only the body. The page shell and
  // hidden controls must not rebuild on a scrolling chapter boundary.
  final _contentRevision = ValueNotifier<int>(0);

  void _refreshContent() => _contentRevision.value++;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _position = ref.read(readerPositionProvider(widget.bookId).notifier);
    ref.listenManual(bookDetailProvider(widget.bookId), (_, next) {});
    ref.listenManual(bookCatalogProvider(widget.bookId), (_, next) {});
    ref.listenManual(readerPositionProvider(widget.bookId), (_, next) {
      if (_catalog != null && next.chapterIndex != _targetIndex) {
        _activate(
          next.chapterIndex,
          offset: next.charOffset,
          writePosition: false,
        );
      }
    });
    ref.listenManual(readerJumpProvider(widget.bookId), (_, next) {
      if (next != null && _catalog != null) {
        _activate(next.chapterIndex, fromEnd: next.fromEnd);
      }
    });
    unawaited(_open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushProgress();
    _contentRevision.dispose();
    super.dispose();
  }

  void _flushProgress() {
    unawaited(
      _position.flush().catchError((Object error, StackTrace stack) {
        _logger.error(
          'Could not save reading progress.',
          error: error,
          stackTrace: stack,
        );
      }),
    );
  }

  late final _logger = ref.read(appLoggerProvider);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flushProgress();
  }

  Future<void> _open() async {
    final epoch = ++_epoch;
    _loading.clear();
    setState(() => _openError = null);
    try {
      final logger = _logger;
      await Future.wait([
        _position.restore(
          ref.read(readingProgressStoreProvider),
          onError: (error, stack) => logger.error(
            'Could not save reading progress.',
            error: error,
            stackTrace: stack,
          ),
        ),
        ref
            .read(readerSettingsProvider.notifier)
            .initialize(ref.read(preferencesStoreProvider), _logger),
      ]);
      if (!mounted || epoch != _epoch) return;
      final detail = await ref.read(bookDetailProvider(widget.bookId).future);
      if (!mounted || epoch != _epoch) return;
      final catalog = await ref.read(bookCatalogProvider(widget.bookId).future);
      if (!mounted || epoch != _epoch) return;
      _detail = detail;
      _position.bindCatalog(catalog);
      _catalog = catalog;
      if (catalog.chapters.isEmpty) {
        setState(() {});
        return;
      }
      final saved = ref.read(readerPositionProvider(widget.bookId));
      final entry = widget.initialChapterId;
      final target = entry == null
          ? saved.chapterIndex.clamp(0, catalog.chapters.length - 1)
          : catalog.chapters.indexWhere((c) => c.id == entry);
      if (target < 0) throw StateError('Chapter not found');
      _activate(target, offset: entry == null ? saved.charOffset : 0);
      setState(() {});
    } catch (error, stack) {
      _logger.error('Could not open reader.', error: error, stackTrace: stack);
      if (mounted && epoch == _epoch) setState(() => _openError = error);
    }
  }

  void _activate(
    int index, {
    int offset = 0,
    bool fromEnd = false,
    bool writePosition = true,
  }) {
    final catalog = _catalog;
    if (catalog == null || index < 0 || index >= catalog.chapters.length) {
      return;
    }
    _targetIndex = index;
    _loaded.removeWhere((key, _) => (key - index).abs() > 1);
    _errors.removeWhere((key, _) => (key - index).abs() > 1);
    _includeMemoryNeighbours(index);
    if (writePosition) {
      final end = _loaded[index]?.body.length ?? (1 << 30);
      ref
          .read(readerPositionProvider(widget.bookId).notifier)
          .update(index, fromEnd ? end : offset);
    }
    _rebuildWindow();
    _refreshContent();
    unawaited(_loadChapter(index));
    if (_loaded.containsKey(index)) _prefetchAfterFrame(index);
  }

  Future<void> _loadChapter(int index) {
    final catalog = _catalog;
    if (catalog == null ||
        index < 0 ||
        index >= catalog.chapters.length ||
        _loaded.containsKey(index)) {
      return Future<void>.value();
    }
    return _loading[index] ??= _fetchChapter(index, _epoch);
  }

  Future<void> _fetchChapter(int index, int epoch) async {
    _errors.remove(index);
    try {
      final chapter = await ref
          .read(bookRepositoryProvider)
          .getChapter(widget.bookId, _catalog!.chapters[index]);
      if (!mounted || epoch != _epoch || (index - _targetIndex).abs() > 1) {
        return;
      }
      _loaded[index] = chapter;
      _position.registerChapter(chapter);
      if (index == _targetIndex) {
        _includeMemoryNeighbours(index);
        final position = ref.read(readerPositionProvider(widget.bookId));
        ref
            .read(readerPositionProvider(widget.bookId).notifier)
            .update(index, position.charOffset.clamp(0, chapter.body.length));
      }
      _rebuildWindow();
      _refreshContent();
      if (index == _targetIndex) _prefetchAfterFrame(index);
    } catch (error) {
      if (mounted && epoch == _epoch && (index - _targetIndex).abs() <= 1) {
        _errors[index] = error;
        _refreshContent();
      }
    } finally {
      if (epoch == _epoch) unawaited(_loading.remove(index));
    }
  }

  void _includeMemoryNeighbours(int index) {
    final catalog = _catalog!;
    final repository = ref.read(bookRepositoryProvider);
    for (final neighbour in [index - 1, index + 1]) {
      if (neighbour < 0 ||
          neighbour >= catalog.chapters.length ||
          _loaded.containsKey(neighbour)) {
        continue;
      }
      final chapter = repository.getMemoryChapter(
        widget.bookId,
        catalog.chapters[neighbour],
      );
      if (chapter == null) continue;
      _loaded[neighbour] = chapter;
      _errors.remove(neighbour);
      _position.registerChapter(chapter);
    }
  }

  void _prefetchAfterFrame(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index != _targetIndex) return;
      // 当前章先展示，下一章优先。失败只记录在边界，不影响当前阅读。
      unawaited(_loadChapter(index + 1));
      unawaited(_loadChapter(index - 1));
    });
  }

  void _rebuildWindow() {
    if (!_loaded.containsKey(_targetIndex)) {
      _window = null;
      return;
    }
    final chapters = [
      for (var i = _targetIndex - 1; i <= _targetIndex + 1; i++) ?_loaded[i],
    ];
    final previous = _window?.chapters;
    if (previous != null &&
        previous.length == chapters.length &&
        List.generate(
          chapters.length,
          (i) => identical(previous[i], chapters[i]),
        ).every((same) => same)) {
      return;
    }
    _window = Book(
      id: widget.bookId,
      title: _detail!.summary.title,
      chapters: chapters,
      totalChapters: _catalog!.chapters.length,
    );
  }

  void _toggleMenu() => setState(() => _menuVisible = !_menuVisible);

  Widget _chapterStatus(int index) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: _errors.containsKey(index)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load chapter ${index + 1}.'),
                TextButton.icon(
                  onPressed: () {
                    _errors.remove(index);
                    _refreshContent();
                    unawaited(_loadChapter(index));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            )
          : _ChapterLoading(
              key: ValueKey((index, index == _targetIndex)),
              chapterNumber: index + 1,
              delayed: index != _targetIndex,
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final brightness = ref.watch(readerBrightnessProvider.notifier);
    final mode = ref.watch(readerSettingsProvider.select((s) => s.mode));
    final catalog = _catalog;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _flushProgress();
          unawaited(brightness.release());
        }
      },
      child: ReaderTheme(
        child: Scaffold(
          body: _openError != null
              ? Center(
                  child: TextButton(
                    onPressed: () {
                      ref.invalidate(bookCatalogProvider(widget.bookId));
                      ref.invalidate(bookDetailProvider(widget.bookId));
                      unawaited(_open());
                    },
                    child: const Text('Could not open this book. Retry'),
                  ),
                )
              : catalog == null
              ? const Center(child: CircularProgressIndicator())
              : catalog.chapters.isEmpty
              ? const Center(child: Text('No chapters available'))
              : Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          SafeArea(
                            bottom: false,
                            child: ExcludeSemantics(
                              excluding: _menuVisible,
                              child: Consumer(
                                builder: (context, ref, _) {
                                  final index = ref.watch(
                                    readerPositionProvider(widget.bookId)
                                        .select((p) => p.chapterIndex),
                                  );
                                  return ReaderChapterBar(
                                    chapterTitle: catalog.chapters[index].title,
                                    onToggleMenu: _toggleMenu,
                                  );
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: MediaQuery.removePadding(
                              context: context,
                              removeTop: true,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ValueListenableBuilder<int>(
                                      valueListenable: _contentRevision,
                                      builder: (context, _, child) =>
                                          _window == null
                                          ? GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: _toggleMenu,
                                              child: _chapterStatus(
                                                _targetIndex,
                                              ),
                                            )
                                          : mode == ReaderMode.paged
                                          ? PagedReader(
                                              key: ValueKey(widget.bookId),
                                              book: _window!,
                                              onToggleMenu: _toggleMenu,
                                              boundaryBuilder: _chapterStatus,
                                            )
                                          : ScrollReader(
                                              key: ValueKey(widget.bookId),
                                              book: _window!,
                                              onToggleMenu: _toggleMenu,
                                              boundaryBuilder: _chapterStatus,
                                            ),
                                    ),
                                  ),
                                  if (_menuVisible)
                                    Positioned(
                                      right: 14,
                                      bottom:
                                          MediaQuery.paddingOf(context).bottom +
                                          ReaderBottomBar.height +
                                          16,
                                      child: ReaderSaveButton(
                                        book: _detail!.summary,
                                      ),
                                    ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: IgnorePointer(
                                      ignoring: !_menuVisible,
                                      child: AnimatedSlide(
                                        offset: _menuVisible
                                            ? Offset.zero
                                            : const Offset(0, 1),
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        child: ReaderBottomBar(
                                          catalog: catalog,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: !_menuVisible,
                        child: AnimatedSlide(
                          offset: _menuVisible
                              ? Offset.zero
                              : const Offset(0, -1),
                          duration: const Duration(milliseconds: 180),
                          child: SafeArea(
                            bottom: false,
                            child: Consumer(
                              builder: (context, ref, _) {
                                // Hidden toolbars need no chapter subscription.
                                final index = _menuVisible
                                    ? ref.watch(
                                        readerPositionProvider(widget.bookId)
                                            .select((p) => p.chapterIndex),
                                      )
                                    : _targetIndex;
                                return ReaderTopBar(
                                  book: _detail!.summary,
                                  chapter: catalog.chapters[index],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Avoid flashing a loading indicator for fast file/cache reads at a boundary.
/// The current chapter still shows its loading state immediately.
class _ChapterLoading extends StatefulWidget {
  const _ChapterLoading({
    super.key,
    required this.chapterNumber,
    required this.delayed,
  });

  final int chapterNumber;
  final bool delayed;

  @override
  State<_ChapterLoading> createState() => _ChapterLoadingState();
}

class _ChapterLoadingState extends State<_ChapterLoading> {
  Timer? _timer;
  late bool _visible;

  @override
  void initState() {
    super.initState();
    _visible = !widget.delayed;
    if (!_visible) {
      _timer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_visible
      ? const SizedBox.shrink()
      : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading chapter ${widget.chapterNumber}…'),
          ],
        );
}
