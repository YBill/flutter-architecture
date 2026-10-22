import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../logic/paragraph_splitter.dart';
import '../../books/domain/book.dart';
import '../domain/reader_settings.dart';
import '../state/reader_providers.dart';

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
}

class _ScrollReaderState extends ConsumerState<ScrollReader> {
  final _scrollController = ItemScrollController();
  final _positionsListener = ItemPositionsListener.create();

  late List<ChapterParagraphs> _paragraphs;
  late List<_ScrollEntry> _entries;
  late List<int> _chapterHeaderItems;
  late int _initialItem;
  late int _currentItem;
  int _handledJumpSeq = -1;
  EdgeInsets? _lastInsets;
  Size? _lastSize;
  int _jumpGeneration = 0;
  bool _restoring = true;
  double _currentAlignment = 0;
  int? _requestedBoundary;
  final _paragraphCache = <Chapter, ChapterParagraphs>{};

  @override
  void initState() {
    super.initState();
    _rebuildEntries();
    final pos = ref.read(readerPositionProvider(widget.book.id));
    _initialItem = _itemForPosition(pos.chapterIndex, pos.charOffset);
    _currentItem = _initialItem;
    _positionsListener.itemPositions.addListener(_writeBackPosition);
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_writeBackPosition);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ScrollReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.book == oldWidget.book) return;
    // 窗口增删章节后按源文字与屏幕偏移恢复，避免预取完成时推走正在读的段落。
    final alignment = _currentAlignment;
    _rebuildEntries();
    final pos = ref.read(readerPositionProvider(widget.book.id));
    _currentItem = _itemForPosition(pos.chapterIndex, pos.charOffset);
    _initialItem = _currentItem;
    _jumpAfterLayout(_currentItem, alignment: alignment);
  }

  void _rebuildEntries() {
    _requestedBoundary = null;
    _paragraphCache.removeWhere(
      (chapter, _) => !widget.book.chapters.contains(chapter),
    );
    _paragraphs = [
      for (final chapter in widget.book.chapters)
        _paragraphCache.putIfAbsent(
          chapter,
          () => splitParagraphs(chapter.body),
        ),
    ];

    _entries = [];
    _chapterHeaderItems = [];
    if (widget.book.chapters.first.index > 0) {
      _entries.add(
        _ScrollEntry(
          chapterIndex: widget.book.chapters.first.index - 1,
          paragraphIndex: -1,
          charOffset: 0,
          isBoundary: true,
        ),
      );
    }
    for (var c = 0; c < widget.book.chapters.length; c++) {
      _chapterHeaderItems.add(_entries.length);
      _entries.add(
        _ScrollEntry(
          chapterIndex: widget.book.chapters[c].index,
          paragraphIndex: -1,
          charOffset: 0,
        ),
      );
      final paragraphs = _paragraphs[c];
      for (var i = 0; i < paragraphs.texts.length; i++) {
        _entries.add(
          _ScrollEntry(
            chapterIndex: widget.book.chapters[c].index,
            paragraphIndex: i,
            charOffset: paragraphs.starts[i],
            text: paragraphs.texts[i],
            isLastInChapter: i == paragraphs.texts.length - 1,
            endsParagraph: paragraphs.endsParagraph[i],
          ),
        );
      }
    }
    if (widget.book.chapters.last.index < widget.book.chapterCount - 1) {
      _entries.add(
        _ScrollEntry(
          chapterIndex: widget.book.chapters.last.index + 1,
          paragraphIndex: -1,
          charOffset: 0,
          isBoundary: true,
        ),
      );
    }
  }

  /// 章首定位到标题，其余定位到包含该 offset 的段落。
  int _itemForPosition(int chapterIndex, int charOffset) {
    final c = widget.book
        .localIndex(chapterIndex)
        .clamp(0, widget.book.chapters.length - 1);
    final paragraphs = _paragraphs[c];
    if (charOffset <= 0 || paragraphs.isEmpty) return _chapterHeaderItems[c];
    return _chapterHeaderItems[c] + 1 + paragraphs.indexForOffset(charOffset);
  }

  void _jumpAfterLayout(int item, {double alignment = 0}) {
    _restoring = true;
    final generation = ++_jumpGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _jumpGeneration ||
          !_scrollController.isAttached) {
        return;
      }
      _scrollController.jumpTo(index: item, alignment: alignment);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _jumpGeneration) return;
        _restoring = false;
        _writeBackPosition();
      });
    });
  }

  void _onJump(JumpRequest? request) {
    if (request == null || request.seq == _handledJumpSeq) return;
    _handledJumpSeq = request.seq;
    final c = widget.book.localIndex(request.chapterIndex);
    if (c < 0) return;
    _currentAlignment = 0;
    final offset = request.fromEnd ? widget.book.chapters[c].body.length : 0;
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
              fromEnd: entry.chapterIndex < widget.book.chapters.first.index,
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

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onToggleMenu,
          child: Padding(
            padding: EdgeInsets.only(
              top: insets.top,
              left: insets.left,
              right: insets.right,
            ),
            child: ScrollablePositionedList.builder(
              key: ValueKey(widget.book.id),
              initialScrollIndex: _initialItem,
              itemCount: _entries.length,
              itemScrollController: _scrollController,
              itemPositionsListener: _positionsListener,
              padding: EdgeInsets.only(top: 12, bottom: insets.bottom + 24),
              itemBuilder: (context, index) =>
                  _buildItem(_entries[index], settings),
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
    if (entry.isHeader) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        child: Text(
          widget
              .book
              .chapters[widget.book.localIndex(entry.chapterIndex)]
              .title,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            inherit: false,
            fontSize: settings.fontSize * 1.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: settings.textColor,
          ),
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
