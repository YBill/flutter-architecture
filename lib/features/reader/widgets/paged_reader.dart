import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/paginator.dart';
import '../../books/domain/book.dart';
import '../domain/reader_settings.dart';
import '../state/reader_providers.dart';

/// 左右翻页模式。
/// 当前章与相邻章的分页结果拼成一条页序列塞进单个 PageView：
/// 页与页、章与章滑动天然无缝（嵌套双 PageView 的手势不会自动接力）。
class PagedReader extends ConsumerStatefulWidget {
  const PagedReader({
    super.key,
    required this.book,
    required this.onToggleMenu,
    this.boundaryBuilder,
  });

  final Book book;
  final VoidCallback onToggleMenu;
  final Widget Function(int chapterIndex)? boundaryBuilder;

  @override
  ConsumerState<PagedReader> createState() => _PagedReaderState();
}

class _LayoutKey {
  const _LayoutKey(
    this.bookId,
    this.fontSize,
    this.lineHeight,
    this.size,
    this.insets,
    this.locale,
  );

  final String bookId;
  final double fontSize;
  final double lineHeight;
  final Size size;
  final EdgeInsets insets;
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      other is _LayoutKey &&
      other.bookId == bookId &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.size == size &&
      other.insets == insets &&
      other.locale == locale;

  @override
  int get hashCode =>
      Object.hash(bookId, fontSize, lineHeight, size, insets, locale);
}

class _Pagination {
  _Pagination(this.book, this.chapterBreaks)
    : chapterPageStart = _cumulative(chapterBreaks);

  final List<List<PageBreak>> chapterBreaks;
  final Book book;
  final List<int> chapterPageStart;

  static List<int> _cumulative(List<List<PageBreak>> breaks) {
    final starts = <int>[0];
    for (var i = 0; i < breaks.length - 1; i++) {
      starts.add(starts.last + breaks[i].length);
    }
    return starts;
  }

  int get leading => book.chapters.first.index > 0 ? 1 : 0;
  int get trailing => book.chapters.last.index < book.chapterCount - 1 ? 1 : 0;
  int get contentTotal => chapterPageStart.last + chapterBreaks.last.length;
  int get total => leading + contentTotal + trailing;
  int? boundaryAt(int page) => page < leading
      ? book.chapters.first.index - 1
      : page >= leading + contentTotal
      ? book.chapters.last.index + 1
      : null;

  (int, int) locate(int globalPage) {
    globalPage -= leading;
    var c = 0;
    for (var i = chapterPageStart.length - 1; i >= 0; i--) {
      if (globalPage >= chapterPageStart[i]) {
        c = i;
        break;
      }
    }
    return (c, globalPage - chapterPageStart[c]);
  }

  int globalOf(int chapterIndex, int pageIndex) =>
      leading + chapterPageStart[chapterIndex] + pageIndex;
}

/// 同一布局条件下缓存最近 10 章的分页，切换模式、移动正文窗口时复用。
class _PaginationCache {
  _LayoutKey? key;
  final chapters = <String, (Chapter, List<PageBreak>)>{};
  void prepare(_LayoutKey next) {
    if (key != next) {
      chapters.clear();
      key = next;
    }
  }

  String _id(Chapter chapter) =>
      chapter.id.isEmpty ? '${chapter.index}' : chapter.id;
  List<PageBreak>? get(Chapter chapter) {
    final entry = chapters.remove(_id(chapter));
    if (entry == null) return null;
    if (entry.$1.version != chapter.version ||
        entry.$1.title != chapter.title ||
        entry.$1.body != chapter.body) {
      return null;
    }
    chapters[_id(chapter)] = entry;
    return entry.$2;
  }

  void put(Chapter chapter, List<PageBreak> breaks) {
    chapters.remove(_id(chapter));
    chapters[_id(chapter)] = (chapter, breaks);
    while (chapters.length > 10) {
      chapters.remove(chapters.keys.first);
    }
  }
}

final _paginationCacheProvider = Provider((ref) => _PaginationCache());

class _PagedReaderState extends ConsumerState<PagedReader> {
  static const _pagePadding = EdgeInsets.fromLTRB(22, 14, 22, 36);
  static const _titleGap = 16.0;
  static const _heightSafety = 2.0;

  PageController? _controller;
  _LayoutKey? _layoutKey;
  _Pagination? _pagination;
  EdgeInsets _insets = EdgeInsets.zero;
  int _handledJumpSeq = -1;
  int _generation = 0;
  bool _contentDirty = false;
  int _viewGeneration = 0;
  _LayoutKey? _appliedLayoutKey;

  @override
  void didUpdateWidget(covariant PagedReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.book != oldWidget.book) {
      // 章节窗口变化或内容刷新后重新匹配分页，生成完成前保留当前画面。
      _contentDirty = true;
      _generation++;
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller?.dispose();
    super.dispose();
  }

  void _requestPagination(ReaderSettings settings, Size size, Locale? locale) {
    final key = _LayoutKey(
      widget.book.id,
      settings.fontSize,
      settings.lineHeight,
      size,
      _insets,
      locale,
    );
    if (_layoutKey == key && !_contentDirty) return;
    final sameLayout = _layoutKey == key;
    _contentDirty = false;
    _layoutKey = key;
    if (!sameLayout) _pagination = null;
    final generation = ++_generation;
    final cache = ref.read(_paginationCacheProvider);
    cache.prepare(key);
    final cached = [
      for (final chapter in widget.book.chapters) cache.get(chapter),
    ];
    if (cached.every((value) => value != null)) {
      _applyPagination(
        _Pagination(widget.book, [for (final value in cached) value!]),
      );
      return;
    }
    // build 只提交任务，先让加载帧显示出来。快速连续调字号时旧任务自动失效。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        _paginate(settings, key, generation);
      }
    });
  }

  Future<void> _paginate(
    ReaderSettings settings,
    _LayoutKey key,
    int generation,
  ) async {
    final book = widget.book;
    final style = settings.textStyle;
    final contentWidth =
        (key.size.width - _pagePadding.horizontal - key.insets.horizontal)
            .clamp(1.0, double.infinity);
    // 测量与渲染必须用同一 textScaler，否则系统字体缩放会让断行不一致
    final bodyHeight =
        key.size.height -
        _pagePadding.vertical -
        key.insets.vertical -
        _heightSafety;

    final breaks = <List<PageBreak>>[];
    final cache = ref.read(_paginationCacheProvider);
    final slice = Stopwatch()..start();
    for (final chapter in book.chapters) {
      final cached = cache.get(chapter);
      if (cached != null) {
        breaks.add(cached);
        continue;
      }
      final titleHeight = _titleHeight(
        settings,
        chapter.title,
        contentWidth,
        key.locale,
      );
      final chapterBreaks = <PageBreak>[];
      for (final pageBreak in Paginator.paginateChapterPages(
        body: chapter.body,
        style: style,
        maxWidth: contentWidth,
        textScaler: TextScaler.noScaling,
        locale: key.locale,
        heightForPage: (page) =>
            page == 0 ? bodyHeight - titleHeight : bodyHeight,
      )) {
        chapterBreaks.add(pageBreak);
        if (slice.elapsedMilliseconds >= 6) {
          await Future<void>.delayed(Duration.zero);
          if (!mounted || generation != _generation) return;
          slice.reset();
        }
      }
      breaks.add(chapterBreaks);
      cache.put(chapter, chapterBreaks);
    }
    if (!mounted || generation != _generation) return;
    final pagination = _Pagination(book, breaks);
    setState(() => _applyPagination(pagination));
  }

  void _applyPagination(_Pagination pagination) {
    final oldController = _controller;
    final previous = _pagination;
    final keepController =
        oldController != null &&
        previous != null &&
        _appliedLayoutKey == _layoutKey &&
        previous.book.chapters.first.index ==
            pagination.book.chapters.first.index &&
        previous.book.chapters.every(
          (chapter) =>
              pagination.book.chapters.any((next) => identical(chapter, next)),
        );
    _pagination = pagination;
    _appliedLayoutKey = _layoutKey;
    if (keepController) return;
    _viewGeneration++;
    _controller = PageController(
      initialPage: _initialPage(pagination),
      keepPage: false,
    );
    // 旧 PageView 从树上移除后再销毁，避免仍挂载时替换控制器。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => oldController?.dispose(),
    );
  }

  // 用真实标题按渲染同款样式测量：大字号下标题会折行，单字测量会少算行数
  double _titleHeight(
    ReaderSettings s,
    String title,
    double maxWidth,
    Locale? locale,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          inherit: false,
          fontSize: s.fontSize * 1.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      locale: locale,
    )..layout(maxWidth: maxWidth);
    final h = tp.height;
    tp.dispose();
    return h + _titleGap;
  }

  int _initialPage(_Pagination pagination) {
    final pos = ref.read(readerPositionProvider(widget.book.id));
    final c = pagination.book
        .localIndex(pos.chapterIndex)
        .clamp(0, pagination.chapterBreaks.length - 1);
    final p = pos.charOffset <= 0
        ? 0
        : Paginator.pageIndexForOffset(
            pagination.chapterBreaks[c],
            pos.charOffset,
          );
    return pagination.globalOf(c, p);
  }

  void _onExternalJump(JumpRequest? request) {
    if (request == null || request.seq == _handledJumpSeq) return;
    _handledJumpSeq = request.seq;
    final c = widget.book.localIndex(request.chapterIndex);
    if (c < 0) return;
    final offset = request.fromEnd ? widget.book.chapters[c].body.length : 0;
    ref
        .read(readerPositionProvider(widget.book.id).notifier)
        .update(request.chapterIndex, offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pagination = _pagination;
      final controller = _controller;
      if (pagination == null || controller == null || !controller.hasClients) {
        return;
      }
      final local = pagination.book.localIndex(request.chapterIndex);
      if (local < 0) return;
      final p = request.fromEnd
          ? pagination.chapterBreaks[local].length - 1
          : 0;
      controller.jumpToPage(pagination.globalOf(local, p));
    });
  }

  void _onPageChanged(int globalPage, _Pagination pagination) {
    if (pagination != _pagination) return;
    final boundary = pagination.boundaryAt(globalPage);
    if (boundary != null) {
      ref
          .read(readerJumpProvider(widget.book.id).notifier)
          .jumpToChapter(
            boundary,
            fromEnd: boundary < pagination.book.chapters.first.index,
          );
      return;
    }
    final (c, p) = pagination.locate(globalPage);
    ref
        .read(readerPositionProvider(widget.book.id).notifier)
        .update(
          pagination.book.chapters[c].index,
          pagination.chapterBreaks[c][p].start,
        );
  }

  void _pageBy(int delta, _Pagination pagination) {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final target = (controller.page!.round() + delta).clamp(
      0,
      pagination.total - 1,
    );
    controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _handleTapUp(TapUpDetails details, Size size, _Pagination pagination) {
    final dx = details.localPosition.dx;
    if (dx < size.width * 0.3) {
      _pageBy(-1, pagination);
    } else if (dx > size.width * 0.7) {
      _pageBy(1, pagination);
    } else {
      widget.onToggleMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Own a position subscription even when embedded without ReaderPage.
    ref.listen(readerPositionProvider(widget.book.id), (_, next) {});
    final settings = ref.watch(readerSettingsProvider);
    ref.listen(
      readerJumpProvider(widget.book.id),
      (_, next) => _onExternalJump(next),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _insets = MediaQuery.paddingOf(context);
        _requestPagination(
          settings,
          size,
          Localizations.maybeLocaleOf(context),
        );
        final pagination = _pagination;
        if (pagination == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return GestureDetector(
          onTapUp: (details) => _handleTapUp(details, size, pagination),
          child: PageView.builder(
            key: ValueKey(_viewGeneration),
            controller: _controller,
            itemCount: pagination.total,
            onPageChanged: (g) => _onPageChanged(g, pagination),
            itemBuilder: (context, g) {
              final boundary = pagination.boundaryAt(g);
              if (boundary != null) {
                return widget.boundaryBuilder?.call(boundary) ??
                    const Center(child: CircularProgressIndicator());
              }
              final (c, p) = pagination.locate(g);
              return _buildPage(
                chapter: pagination.book.chapters[c],
                pageBreak: pagination.chapterBreaks[c][p],
                pageIndex: p,
                pageCount: pagination.chapterBreaks[c].length,
                settings: settings,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPage({
    required Chapter chapter,
    required PageBreak pageBreak,
    required int pageIndex,
    required int pageCount,
    required ReaderSettings settings,
  }) {
    final text = Paginator.pageText(chapter.body, pageBreak);
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            _pagePadding.left + _insets.left,
            _pagePadding.top + _insets.top,
            _pagePadding.right + _insets.right,
            _pagePadding.bottom + _insets.bottom,
          ),
          // 正常页面高度已经校验；极矮窗口或超长标题仍允许纵向读完，不能裁掉正文。
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pageIndex == 0) ...[
                  Text(
                    chapter.title,
                    textDirection: TextDirection.ltr,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      inherit: false,
                      fontSize: settings.fontSize * 1.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: settings.textColor,
                    ),
                  ),
                  const SizedBox(height: _titleGap),
                ],
                Text(
                  text,
                  textDirection: TextDirection.ltr,
                  textScaler: TextScaler.noScaling,
                  style: settings.textStyle,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 16 + _insets.right,
          bottom: 10 + _insets.bottom,
          child: Text(
            '${pageIndex + 1}/$pageCount',
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: 12, color: settings.secondaryTextColor),
          ),
        ),
      ],
    );
  }
}
