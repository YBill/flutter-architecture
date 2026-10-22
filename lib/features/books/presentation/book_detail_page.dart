import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../application/book_providers.dart';
import '../domain/book.dart';
import '../domain/chapter_preview.dart';
import 'widgets/book_cover.dart';

const _ink = Color(0xFF201734);
const _purple = Color(0xFF6A48DF);
const _cream = Color(0xFFFFFDFA);
const _muted = Color(0xFF85808F);
const _detailOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: _cream,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);
const _serif = TextStyle(
  fontFamily: 'Georgia',
  fontFamilyFallback: ['Times New Roman', 'serif'],
  letterSpacing: -.5,
);

class BookDetailPage extends ConsumerStatefulWidget {
  const BookDetailPage({required this.bookId, super.key});
  final String bookId;

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  final _scroll = ScrollController();
  bool _saving = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _read() => unawaited(
    context.pushNamed<void>(
      'reader',
      pathParameters: {'bookId': widget.bookId},
    ),
  );

  Future<void> _toggleLibrary(BookDetail detail) async {
    setState(() => _saving = true);
    try {
      await ref.read(bookLibraryRepositoryProvider).toggle(detail.summary);
    } catch (_) {
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).actionFailed)),
    );
  }

  Future<void> _share(BookDetail detail, BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${detail.summary.title}\n${detail.summary.author}\n\n${detail.description}',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) _showError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(bookDetailProvider(widget.bookId));
    final book = detail.asData?.value;
    final saved = ref.watch(bookSavedProvider(widget.bookId));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _detailOverlay,
      child: Theme(
        // The prototype is a light book jacket; reader night mode is independent.
        data: Theme.of(context).copyWith(
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _purple,
            surface: _cream,
          ),
          textTheme: ThemeData.light().textTheme.apply(
            bodyColor: _ink,
            displayColor: _ink,
          ),
        ),
        child: Scaffold(
          backgroundColor: _cream,
          bottomNavigationBar: _bottomBar(
            book,
            saved.asData?.value ?? false,
            l10n,
          ),
          body: CustomScrollView(
            key: const PageStorageKey('book-detail-scroll'),
            controller: _scroll,
            slivers: [
              _topBar(book, l10n),
              ...detail.when(
                loading: () => [
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: _purple),
                    ),
                  ),
                ],
                error: (_, _) => [
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.bookLoadFailed),
                          TextButton(
                            onPressed: () => ref.invalidate(
                              bookDetailProvider(widget.bookId),
                            ),
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                data: (detail) => _content(detail, l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BookDetail? book, AppLocalizations l10n) => ListenableBuilder(
    listenable: _scroll,
    builder: (context, child) {
      // Reparenting during hot reload can briefly retain the old scroll view.
      final offset = _scroll.positions.lastOrNull?.pixels ?? 0.0;
      final backgroundOpacity = Curves.easeOut.transform(
        (offset / 112).clamp(0.0, 1.0),
      );
      final titleOpacity = Curves.easeOut.transform(
        ((offset - 48) / 64).clamp(0.0, 1.0),
      );
      return SliverAppBar(
        pinned: true,
        toolbarHeight: 52,
        systemOverlayStyle: _detailOverlay,
        backgroundColor: _cream.withValues(alpha: backgroundOpacity),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(
          bottom: BorderSide(color: _ink.withValues(alpha: .06 * titleOpacity)),
        ),
        centerTitle: true,
        foregroundColor: _ink,
        leading: IconButton(
          disabledColor: _ink,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: context.canPop() ? () => context.pop() : null,
        ),
        title: ExcludeSemantics(
          excluding: titleOpacity == 0,
          child: Opacity(
            key: const ValueKey('book-detail-toolbar-title'),
            opacity: titleOpacity,
            child: Transform.translate(
              offset: Offset(0, 4 * (1 - titleOpacity)),
              child: Text(
                book?.summary.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        actions: [
          Builder(
            builder: (anchor) => IconButton(
              tooltip: l10n.shareBook,
              onPressed: book == null
                  ? null
                  : () => unawaited(_share(book, anchor)),
              icon: const Icon(Icons.ios_share_rounded, size: 23),
            ),
          ),
          const SizedBox(width: 10),
        ],
      );
    },
  );

  List<Widget> _content(BookDetail detail, AppLocalizations l10n) {
    final first = detail.firstChapter;
    return [
      SliverToBoxAdapter(
        child: DecoratedBox(
          key: const ValueKey('book-detail-header'),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_cream, Color(0xFFF0EAF8), _cream],
              stops: [0, .35, 1],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BookHeader(detail: detail, l10n: l10n),
                    const SizedBox(height: 12),
                    _Statistics(detail: detail, l10n: l10n),
                    const SizedBox(height: 18),
                    _BookSynopsis(text: detail.description, l10n: l10n),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2ECFF),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          l10n.chapterPreview,
                          style: const TextStyle(
                            color: Color(0xFF7655B9),
                            fontSize: 10,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (first != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      first.title,
                      textAlign: TextAlign.center,
                      style: _serif.copyWith(
                        fontSize: 21,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ChapterPreview(chapter: first, onRead: _read, l10n: l10n),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: TextButton(
                        onPressed: _read,
                        child: Text(l10n.continueReading),
                      ),
                    ),
                  const SizedBox(height: 42),
                  Text(
                    l10n.youMightLike,
                    style: _serif.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 13),
                  _Recommendations(bookId: widget.bookId),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _bottomBar(BookDetail? detail, bool saved, AppLocalizations l10n) =>
      DecoratedBox(
        decoration: const BoxDecoration(
          color: _cream,
          border: Border(top: BorderSide(color: Color(0xFFEDE4F4))),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('start-reading'),
                      onPressed: detail == null ? null : _read,
                      style: FilledButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        l10n.startFreeReading,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Semantics(
                    selected: saved,
                    child: OutlinedButton(
                      key: const ValueKey('save-book'),
                      onPressed: detail == null || _saving
                          ? null
                          : () => unawaited(_toggleLibrary(detail)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _purple,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 12,
                        ),
                        side: const BorderSide(color: Color(0xFFAA84ED)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            saved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.library,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _BookHeader extends StatelessWidget {
  const _BookHeader({required this.detail, required this.l10n});
  final BookDetail detail;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 92, height: 138, child: BookCover(book: detail.summary)),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail.summary.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _serif.copyWith(
                fontSize: 23,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            _BookTags(tags: detail.tags.toSet().take(2).toList()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.chapterCount(detail.summary.chapterCount),
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: Color(0xFF95849F),
                  ),
                ),
                if (detail.status.isNotEmpty)
                  _Tag(
                    detail.status == 'Completed'
                        ? l10n.completed
                        : detail.status,
                    status: true,
                  ),
              ],
            ),
            if (detail.category.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Tag(detail.category, pill: true),
            ],
          ],
        ),
      ),
    ],
  );
}

class _BookTags extends StatelessWidget {
  const _BookTags({required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final visible = <String>[];
      var used = 0.0;
      for (final tag in tags) {
        final painter = TextPainter(
          text: TextSpan(
            text: tag,
            style: const TextStyle(fontSize: 10, height: 1.5),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width + 10 + (visible.isEmpty ? 0 : 4);
        painter.dispose();
        if (used + width > constraints.maxWidth) continue;
        visible.add(tag);
        used += width;
      }
      return Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _Tag(visible[i]),
          ],
        ],
      );
    },
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.pill = false, this.status = false});
  final String text;
  final bool pill;
  final bool status;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: pill
          ? 6
          : status
          ? 7
          : 5,
      vertical: pill || status ? 3 : 2,
    ),
    decoration: BoxDecoration(
      color: pill
          ? const Color(0xFFE7D7F7)
          : status
          ? const Color(0xFFEEE8F5)
          : const Color(0xFFF0E8F8),
      borderRadius: BorderRadius.circular(
        pill
            ? 20
            : status
            ? 5
            : 4,
      ),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: pill
            ? const Color(0xFF7443A2)
            : status
            ? const Color(0xFF887098)
            : const Color(0xFF8B65AA),
        fontSize: pill ? 9 : 10,
        height: 1.5,
        fontWeight: pill ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  );
}

class _BookSynopsis extends StatefulWidget {
  const _BookSynopsis({required this.text, required this.l10n});
  final String text;
  final AppLocalizations l10n;

  @override
  State<_BookSynopsis> createState() => _BookSynopsisState();
}

class _BookSynopsisState extends State<_BookSynopsis> {
  bool _expanded = false;
  static const _style = TextStyle(
    fontSize: 12,
    height: 1.65,
    color: Color(0xFF71697C),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: _style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 4,
      )..layout(maxWidth: constraints.maxWidth);
      final overflowing = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            key: const ValueKey('book-synopsis'),
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: _style,
          ),
          if (overflowing)
            Semantics(
              expanded: _expanded,
              child: TextButton(
                key: const ValueKey('toggle-synopsis'),
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  foregroundColor: _purple,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(
                  _expanded ? widget.l10n.showLess : widget.l10n.readMore,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _Statistics extends StatelessWidget {
  const _Statistics({required this.detail, required this.l10n});
  final BookDetail detail;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final compact = NumberFormat.compact(
      locale: Localizations.localeOf(context).toLanguageTag(),
    )..maximumFractionDigits = 1;
    Widget stat(
      IconData icon,
      String value,
      String label, {
      bool rating = false,
    }) => Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: rating
                    ? const Color(0xFFCA9B4F)
                    : const Color(0xFFA46BD1),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: value,
                    children: [
                      if (rating)
                        const TextSpan(
                          text: ' / 5',
                          style: TextStyle(color: _muted, fontSize: 10),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF49345E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              height: 1.5,
              color: Color(0xFF96859F),
            ),
          ),
        ],
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2FC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            stat(
              Icons.menu_book_outlined,
              compact.format(detail.readerCount),
              l10n.readers,
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0xFFE5DBEE),
            ),
            stat(
              Icons.favorite_border_rounded,
              compact.format(detail.savedCount),
              l10n.savedReaders,
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0xFFE5DBEE),
            ),
            stat(
              Icons.star_rounded,
              detail.rating.toStringAsFixed(1),
              l10n.rating,
              rating: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterPreview extends StatelessWidget {
  const _ChapterPreview({
    required this.chapter,
    required this.onRead,
    required this.l10n,
  });
  final Chapter chapter;
  final VoidCallback onRead;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Text(
        chapterPreview(chapter.body),
        key: const ValueKey('chapter-preview-text'),
        style: _serif.copyWith(
          fontSize: 17,
          height: 1.85,
          letterSpacing: 0,
          color: const Color(0xFF292231),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          height: 100,
          alignment: Alignment.bottomCenter,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x00FFFFFF),
                Color(0xBFFFFFFF),
                Color(0xFAFFFFFF),
                Colors.white,
              ],
              stops: [0, .45, .74, 1],
            ),
          ),
          child: TextButton(
            key: const ValueKey('continue-reading'),
            onPressed: onRead,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8051C9),
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.fromLTRB(18, 11, 18, 8),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    l10n.continueReading,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.arrow_forward_rounded, size: 15),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _Recommendations extends ConsumerWidget {
  const _Recommendations({required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(bookRecommendationsProvider(bookId))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: _purple)),
          ),
          error: (_, _) => TextButton.icon(
            onPressed: () =>
                ref.invalidate(bookRecommendationsProvider(bookId)),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.recommendationsFailed),
          ),
          data: (items) => LayoutBuilder(
            builder: (context, constraints) {
              final scaled = MediaQuery.textScalerOf(context).scale(1);
              final columns = constraints.maxWidth < 320 || scaled > 1.5
                  ? 2
                  : 3;
              return GridView.builder(
                key: const ValueKey('recommendations'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 16,
                  mainAxisExtent:
                      (constraints.maxWidth - (columns - 1) * 10) /
                          columns *
                          1.45 +
                      37 * scaled,
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Semantics(
                    button: true,
                    label: item.book.title,
                    child: InkWell(
                      key: ValueKey('recommendation-${item.book.id}'),
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => unawaited(
                        context.pushNamed<void>(
                          'book-detail',
                          pathParameters: {'bookId': item.targetBookId},
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 1 / 1.45,
                            child: BookCover(
                              book: item.book,
                              rating: item.rating,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            item.book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _serif.copyWith(
                              fontSize: 11,
                              height: 15 / 11,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
  }
}
