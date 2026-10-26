import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../logic/paragraph_splitter.dart';
import '../../books/domain/book.dart';
import '../domain/reader_settings.dart';
import '../state/reader_providers.dart';
import 'reader_scroll_list.dart';

/// 上下滚动模式。
/// 章节标题 + 段落拍平成一条懒加载列表：超长章节也只构建可见段落，
/// 位置按段首 charOffset 回写，切回左右翻页时可回到具体页。
class ScrollReader extends ConsumerStatefulWidget {
  const ScrollReader({
    super.key,
    required this.book,
    required this.onToggleMenu,
    this.boundaryBuilder,
  });

  final Book book;
  final VoidCallback onToggleMenu;
  final Widget Function(int chapterIndex)? boundaryBuilder;

  @override
  ConsumerState<ScrollReader> createState() => _ScrollReaderState();
}

class _ScrollEntry {
  const _ScrollEntry({
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.charOffset,
    this.text,
    this.isLastInChapter = false,
    this.endsParagraph = true,
    this.isBoundary = false,
  });

  final int chapterIndex;
  final int paragraphIndex; // -1 表示章节标题
  final int charOffset;
  final String? text;
  final bool isLastInChapter;
  final bool endsParagraph;
  final bool isBoundary;

  bool get isHeader => text == null && !isBoundary;
  Object get key => (chapterIndex, paragraphIndex, isBoundary);
}

class _ScrollReaderState extends ConsumerState<ScrollReader> {
  final _scrollController = ReaderItemScrollController();
  final _positionsListener = ReaderItemPositionsListener();

  late List<ChapterParagraphs> _paragraphs;
  late List<_ScrollEntry> _entries;
  late List<Object> _entryKeys;
  late Book _renderBook;
  late List<int> _chapterHeaderItems;
  late int _initialItem;
  late int _currentItem;
  int _handledJumpSeq = -1;
  EdgeInsets? _lastInsets;
  Size? _lastSize;
  int _jumpGeneration = 0;
  int _contentGeneration = 0;
  bool _pendingJump = false;
  double _initialAlignment = 0;
  bool _restoring = true;
  double _currentAlignment = 0;
  int? _requestedBoundary;
  final _paragraphCache = <Chapter, ChapterParagraphs>{};
  final _chapterEntries = <Chapter, List<_ScrollEntry>>{};
  final _itemWidgets = <_ScrollEntry, Widget>{};
  ReaderSettings? _itemSettings;
  bool _scrolling = false;
  bool _compactScheduled = false;
  final _pointers = <int>{};

  // During one continuous gesture retain a small render buffer. Compact it
  // after scrolling, instead of relocating every visible paragraph at a title.
  static const _maxMovingChapters = 10;

  @override
  void initState() {
    super.initState();
    _renderBook = widget.book;
    _rebuildEntries();
    final pos = ref.read(readerPositionProvider(widget.book.id));
    _initialItem = _itemForPosition(pos.chapterIndex, pos.charOffset);
    _currentItem = _initialItem;
    _positionsListener.itemPositions.addListener(_writeBackPosition);
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_writeBackPosition);
    _positionsListener.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ScrollReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.book == oldWidget.book) return;
    _updateRenderBook();
  }

  void _updateRenderBook() {
    final next = widget.book;
    final sameBook = next.id == _renderBook.id;
    final retain =
        next.id == _renderBook.id && (_scrolling || _pointers.isNotEmpty);
    var chapters = next.chapters;
    if (retain) {
      final merged = {
        for (final chapter in _renderBook.chapters) chapter.index: chapter,
        for (final chapter in next.chapters) chapter.index: chapter,
      };
      final target = ref.read(readerPositionProvider(next.id)).chapterIndex;
      while (merged.length > _maxMovingChapters) {
        final furthest = merged.keys.reduce(
          (a, b) => (a - target).abs() > (b - target).abs() ? a : b,
        );
        merged.remove(furthest);
      }
      final indices = merged.keys.toList()..sort();
      chapters = [for (final index in indices) merged[index]!];
    }
    if (_renderBook.id == next.id &&
        chapters.length == _renderBook.chapters.length &&
        Iterable.generate(chapters.length)
            .every((i) => identical(chapters[i], _renderBook.chapters[i]))) {
      return;
    }
    _renderBook = Book(
      id: next.id,
      title: next.title,
      chapters: chapters,
      totalChapters: next.chapterCount,
    );
    // Rebase before layout while keeping the same scroll activity. Replacing
    // the list would stop a drag/fling whenever the chapter window moves.
    final alignment = sameBook ? _currentAlignment : 0.0;
    final oldItem = _currentItem;
    final anchor = _entries[oldItem];
    _rebuildEntries();
    final pos = ref.read(readerPositionProvider(widget.book.id));
    _currentItem =
        sameBook &&
            anchor.chapterIndex == pos.chapterIndex &&
            anchor.charOffset == pos.charOffset
        ? _itemForEntry(anchor)
        : _itemForPosition(pos.chapterIndex, pos.charOffset);
    _initialItem = _currentItem;
    if (!sameBook || _currentItem != oldItem) {
      _initialAlignment = alignment;
      _restoring = true;
      final generation = ++_contentGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _contentGeneration || _pendingJump) {
          return;
        }
        _restoring = false;
      });
    }
  }

  void _onScrollingChanged(bool scrolling) {
    _scrolling = scrolling;
    if (!scrolling) _scheduleCompact();
  }

  void _scheduleCompact() {
    if (_compactScheduled) return;
    _compactScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _compactScheduled = false;
      if (!mounted || _scrolling || _pointers.isNotEmpty || _pendingJump) {
        return;
      }
      setState(_updateRenderBook);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _rebuildEntries() {
    _requestedBoundary = null;
    _paragraphCache.removeWhere(
      (chapter, _) => !_renderBook.chapters.contains(chapter),
    );
    _chapterEntries.removeWhere(
      (chapter, _) => !_renderBook.chapters.contains(chapter),
    );
    _paragraphs = [
      for (final chapter in _renderBook.chapters)
        _paragraphCache.putIfAbsent(
          chapter,
          () => splitParagraphs(chapter.body),
        ),
    ];

    _entries = [];
    _chapterHeaderItems = [];
    if (_renderBook.chapters.first.index > 0) {
      _entries.add(
        _ScrollEntry(
          chapterIndex: _renderBook.chapters.first.index - 1,
          paragraphIndex: -1,
          charOffset: 0,
          isBoundary: true,
        ),
      );
    }
    for (var c = 0; c < _renderBook.chapters.length; c++) {
      _chapterHeaderItems.add(_entries.length);
      final chapter = _renderBook.chapters[c];
      _entries.addAll(
        _chapterEntries.putIfAbsent(
          chapter,
          () => [
            _ScrollEntry(
              chapterIndex: chapter.index,
              paragraphIndex: -1,
              charOffset: 0,
            ),
            for (var i = 0; i < _paragraphs[c].texts.length; i++)
              _ScrollEntry(
                chapterIndex: chapter.index,
                paragraphIndex: i,
                charOffset: _paragraphs[c].starts[i],
                text: _paragraphs[c].texts[i],
                isLastInChapter: i == _paragraphs[c].texts.length - 1,
                endsParagraph: _paragraphs[c].endsParagraph[i],
              ),
          ],
        ),
      );
    }
    if (_renderBook.chapters.last.index < _renderBook.chapterCount - 1) {
      _entries.add(
        _ScrollEntry(
          chapterIndex: _renderBook.chapters.last.index + 1,
          paragraphIndex: -1,
          charOffset: 0,
          isBoundary: true,
        ),
      );
    }
    _entryKeys = [for (final entry in _entries) entry.key];
    final retained = _entries.toSet();
    _itemWidgets.removeWhere((entry, _) => !retained.contains(entry));
  }

  /// 章首定位到标题，其余定位到包含该 offset 的段落。
  int _itemForPosition(int chapterIndex, int charOffset) {
    final c = _renderBook
        .localIndex(chapterIndex)
        .clamp(0, _renderBook.chapters.length - 1);
    final paragraphs = _paragraphs[c];
    if (charOffset <= 0 || paragraphs.isEmpty) return _chapterHeaderItems[c];
    return _chapterHeaderItems[c] + 1 + paragraphs.indexForOffset(charOffset);
  }

  // A header and its first text block can both have offset zero. Internal
  // rebasing must retain the actual item; explicit chapter navigation still
  // uses _itemForPosition to select the header.
  int _itemForEntry(_ScrollEntry anchor) {
    final retained = _entryKeys.indexOf(anchor.key);
    return retained >= 0
        ? retained
        : _itemForPosition(anchor.chapterIndex, anchor.charOffset);
  }

  void _jumpAfterLayout(int item, {double alignment = 0}) {
    final anchor = _entries[item];
    _restoring = true;
    _pendingJump = true;
    final generation = ++_jumpGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _jumpGeneration ||
          !_scrollController.isAttached) {
        return;
      }
      // Prefetch/compaction may have moved flat indexes since the request.
      // Explicit navigation uses its source position in the latest window.
      final target = _itemForEntry(anchor);
      _currentItem = target;
      _scrollController.jumpTo(index: target, alignment: alignment);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _jumpGeneration) return;
        _pendingJump = false;
        _restoring = false;
        _writeBackPosition();
        if (!_scrolling) _scheduleCompact();
      });
    });
  }

  void _onJump(JumpRequest? request) {
    if (request == null || request.seq == _handledJumpSeq) return;
    _handledJumpSeq = request.seq;
    final c = _renderBook.localIndex(request.chapterIndex);
    if (c < 0) return;
    _currentAlignment = 0;
    final offset = request.fromEnd ? _renderBook.chapters[c].body.length : 0;
    _currentItem = _itemForPosition(request.chapterIndex, offset);
    ref
        .read(readerPositionProvider(widget.book.id).notifier)
        .update(request.chapterIndex, offset);
    _jumpAfterLayout(_currentItem);
  }

  void _onSettingsChanged(ReaderSettings? prev, ReaderSettings next) {
    if (prev == null ||
        (prev.fontSize == next.fontSize &&
            prev.lineHeight == next.lineHeight)) {
      return;
    }
    // 字号/行距变化会改变所有段落高度，按当前段重新锚定
    _jumpAfterLayout(_currentItem);
  }

  /// 取视口顶部所在的列表项，回写 (章, 段首 offset)。
  void _writeBackPosition() {
    if (_restoring) return;
    final visible = _positionsListener.itemPositions.value;
    ItemPosition? top;
    for (final position in visible) {
      // 包的监听器还会报告缓存区的 item，必须排除完全离开视口的项。
      if (position.itemTrailingEdge <= 0 ||
          position.itemLeadingEdge >= 1 ||
          position.index < 0 ||
          position.index >= _entries.length) {
        continue;
      }
      if (top == null || position.itemLeadingEdge < top.itemLeadingEdge) {
        top = position;
      }
    }
    if (top == null) return;
    final entry = _entries[top.index];
    if (entry.isBoundary) {
      if (_requestedBoundary != entry.chapterIndex) {
        _requestedBoundary = entry.chapterIndex;
        ref
            .read(readerJumpProvider(widget.book.id).notifier)
            .jumpToChapter(
              entry.chapterIndex,
              fromEnd: entry.chapterIndex < _renderBook.chapters.first.index,
            );
      }
      return;
    }
    _currentItem = top.index;
    _currentAlignment = top.itemLeadingEdge;
    ref
        .read(readerPositionProvider(widget.book.id).notifier)
        .update(entry.chapterIndex, entry.charOffset);
  }

  @override
  Widget build(BuildContext context) {
    // Own a position subscription even when embedded without ReaderPage.
    ref.listen(readerPositionProvider(widget.book.id), (_, next) {});
    final settings = ref.watch(readerSettingsProvider);
    if (!identical(settings, _itemSettings)) {
      _itemWidgets.clear();
      _itemSettings = settings;
    }
    ref.listen(readerSettingsProvider, _onSettingsChanged);
    ref.listen(readerJumpProvider(widget.book.id), (_, next) => _onJump(next));

    final insets = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_lastInsets != insets || _lastSize != constraints.biggest) {
          _lastInsets = insets;
          _lastSize = constraints.biggest;
          _jumpAfterLayout(_currentItem);
        }

        return Listener(
          onPointerDown: (event) => _pointers.add(event.pointer),
          onPointerUp: (event) {
            _pointers.remove(event.pointer);
            _scheduleCompact();
          },
          onPointerCancel: (event) {
            _pointers.remove(event.pointer);
            _scheduleCompact();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onToggleMenu,
            child: Padding(
              padding: EdgeInsets.only(
                top: insets.top,
                left: insets.left,
                right: insets.right,
              ),
              child: ReaderScrollList(
                key: ValueKey(widget.book.id),
                initialScrollIndex: _initialItem,
                initialAlignment: _initialAlignment,
                itemCount: _entries.length,
                itemKeys: _entryKeys,
                onScrollingChanged: _onScrollingChanged,
                itemScrollController: _scrollController,
                itemPositionsListener: _positionsListener,
                padding: EdgeInsets.only(top: 12, bottom: insets.bottom + 24),
                itemBuilder: (context, index) =>
                    _buildItem(_entries[index], settings),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildItem(_ScrollEntry entry, ReaderSettings settings) {
    if (entry.isBoundary) {
      return SizedBox(
        height: 200,
        child:
            widget.boundaryBuilder?.call(entry.chapterIndex) ??
            const Center(child: CircularProgressIndicator()),
      );
    }
    return _itemWidgets.putIfAbsent(
      entry,
      () => _buildTextItem(entry, settings),
    );
  }

  Widget _buildTextItem(_ScrollEntry entry, ReaderSettings settings) {
    if (entry.isHeader) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        child: Text(
          _renderBook
              .chapters[_renderBook.localIndex(entry.chapterIndex)]
              .title,
          textScaler: TextScaler.noScaling,
          style: settings.titleStyle,
        ),
      );
    }
    final gap = settings.fontSize * settings.lineHeight;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        0,
        22,
        (entry.endsParagraph ? gap : 0) + (entry.isLastInChapter ? 28 : 0),
      ),
      child: Text(
        entry.text!.trimRight(),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        style: settings.textStyle,
      ),
    );
  }
}
