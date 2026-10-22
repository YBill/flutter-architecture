import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../books/domain/book.dart';
import '../state/chapter_bookmark_providers.dart';
import '../state/reader_providers.dart';
import '../state/reader_brightness_provider.dart';
import 'reader_sheets.dart';
import 'reader_theme.dart';

/// The compact chapter strip stays mounted below the overlay toolbar.
class ReaderChapterBar extends ConsumerWidget {
  const ReaderChapterBar({
    super.key,
    required this.chapterTitle,
    required this.onToggleMenu,
  });
  static const height = 42.0;
  final String chapterTitle;
  final VoidCallback onToggleMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    return Container(
      key: const ValueKey('reader-chapter-header'),
      height: height,
      decoration: BoxDecoration(
        color: settings.surfaceColor,
        border: Border(bottom: BorderSide(color: settings.dividerColor)),
      ),
      child: InkWell(
        onTap: onToggleMenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              chapterTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: settings.textColor),
            ),
          ),
        ),
      ),
    );
  }
}

class ReaderTopBar extends ConsumerWidget {
  const ReaderTopBar({super.key, required this.book, required this.chapter});
  static const height = 52.0;
  final BookSummary book;
  final ChapterMeta chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    return ColoredBox(
      color: settings.surfaceColor,
      child: SizedBox(
        key: const ValueKey('reader-expanded-header'),
        height: height,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              tooltip: 'Back to book',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Chapter ${chapter.index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: settings.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            ReaderSaveButton(book: book, chapter: chapter),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// Both controls use the same persisted repositories as the detail page.
class ReaderSaveButton extends ConsumerStatefulWidget {
  const ReaderSaveButton({super.key, required this.book, this.chapter});
  final BookSummary book;
  final ChapterMeta? chapter;
  @override
  ConsumerState<ReaderSaveButton> createState() => _ReaderSaveButtonState();
}

class _ReaderSaveButtonState extends ConsumerState<ReaderSaveButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      final chapter = widget.chapter;
      if (chapter == null) {
        await ref.read(bookLibraryRepositoryProvider).toggle(widget.book);
      } else {
        await ref
            .read(chapterBookmarkRepositoryProvider)
            .toggle(widget.book.id, chapter);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save this change. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapter;
    final saved = chapter == null
        ? ref.watch(bookSavedProvider(widget.book.id))
        : ref
              .watch(chapterBookmarksProvider(widget.book.id))
              .whenData((ids) => ids.contains(chapter.id));
    final selected = saved.value ?? false;
    final settings = ref.watch(readerSettingsProvider);
    final button = IconButton(
      key: ValueKey(chapter == null ? 'reader-library' : 'reader-bookmark'),
      tooltip: chapter == null
          ? selected
                ? 'Remove from library'
                : 'Add to library'
          : selected
          ? 'Remove bookmark'
          : 'Add bookmark',
      isSelected: selected,
      onPressed: !_busy && saved.hasValue ? _toggle : null,
      color: chapter == null || selected
          ? AppTheme.primaryColor
          : settings.textColor,
      icon: Icon(
        chapter == null ? Icons.favorite_border : Icons.bookmark_border,
        size: chapter == null ? 21 : 23,
      ),
      selectedIcon: Icon(
        chapter == null ? Icons.favorite : Icons.bookmark,
        size: chapter == null ? 21 : 23,
      ),
    );
    return Semantics(
      selected: selected,
      child: chapter != null
          ? button
          : Material(
              color: settings.surfaceColor,
              shape: CircleBorder(
                side: BorderSide(color: settings.selectedControlColor),
              ),
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              child: SizedBox(width: 44, height: 44, child: button),
            ),
    );
  }
}

class ReaderBottomBar extends ConsumerWidget {
  const ReaderBottomBar({super.key, required this.catalog});
  static const height = 46.0;
  final BookCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    return Container(
      decoration: BoxDecoration(
        color: settings.surfaceColor,
        border: Border(top: BorderSide(color: settings.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          key: const ValueKey('reader-bottom-menu'),
          height: height,
          child: Row(
            children: [
              _MenuAction(
                icon: Icons.format_list_bulleted,
                label: 'Contents',
                onPressed: () =>
                    _showSheet(context, ReaderCatalogSheet(catalog: catalog)),
              ),
              _MenuAction(
                icon: settings.isNightMode
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                label: 'Theme',
                onPressed: () => ref
                    .read(readerSettingsProvider.notifier)
                    .update((s) => s.copyWith(isNightMode: !s.isNightMode)),
              ),
              _MenuAction(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onPressed: () {
                  ref.read(readerBrightnessProvider.notifier).refresh();
                  _showSheet(context, const ReaderSettingsSheet());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, Widget child) {
    final isSettings = child is ReaderSettingsSheet;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: isSettings
          ? Colors.transparent
          : Colors.black.withValues(alpha: 0.38),
      isScrollControlled: true,
      useSafeArea: true,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isSettings ? 20 : 25),
        ),
      ),
      builder: (_) => ReaderTheme(child: child),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Expanded(
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        foregroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFC5A4ED)
            : const Color(0xFF8965A2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
}
