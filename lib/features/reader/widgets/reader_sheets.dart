import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../app/theme/app_theme.dart';
import '../../books/domain/book.dart';
import '../domain/reader_settings.dart';
import '../state/chapter_bookmark_providers.dart';
import '../state/reader_brightness_provider.dart';
import '../state/reader_providers.dart';

const _headingStyle = TextStyle(
  fontFamily: ReaderSettings.serifFontFamily,
  fontFamilyFallback: ReaderSettings.serifFontFallback,
  fontSize: 20,
  height: 1.2,
  fontWeight: FontWeight.w700,
);

class _SheetHeading extends ConsumerWidget {
  const _SheetHeading(this.title, {this.fontSize = 20});
  final String title;
  final double fontSize;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: settings.selectedControlColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 10, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: _headingStyle.copyWith(fontSize: fontSize),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReaderCatalogSheet extends ConsumerWidget {
  const ReaderCatalogSheet({super.key, required this.catalog});
  final BookCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      readerPositionProvider(catalog.bookId).select((p) => p.chapterIndex),
    );
    final bookmarks = ref.watch(chapterBookmarksProvider(catalog.bookId));
    final settings = ref.watch(readerSettingsProvider);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHeading('Chapters'),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(
                '${catalog.chapters.length} chapters',
                style: TextStyle(
                  fontSize: 12,
                  color: settings.secondaryTextColor,
                ),
              ),
            ),
            if (bookmarks.hasError)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(chapterBookmarksProvider(catalog.bookId)),
                  child: const Text('Could not load bookmarks. Retry'),
                ),
              ),
            Expanded(
              child: ScrollablePositionedList.builder(
                initialScrollIndex: current.clamp(
                  0,
                  catalog.chapters.length - 1,
                ),
                itemCount: catalog.chapters.length,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemBuilder: (context, i) {
                  final chapter = catalog.chapters[i];
                  final bookmarked =
                      bookmarks.value?.contains(chapter.id) ?? false;
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: settings.dividerColor),
                      ),
                    ),
                    child: ListTile(
                      key: ValueKey('catalog-${chapter.id}'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 3),
                      dense: true,
                      minTileHeight: 48,
                      minVerticalPadding: 0,
                      selected: current == i,
                      selectedColor: AppTheme.primaryColor,
                      title: Row(
                        children: [
                          Text(
                            '${i + 1}'.padLeft(2, '0'),
                            style: const TextStyle(
                              color: AppTheme.primaryColor,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              chapter.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: current == i
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (bookmarked)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.bookmark,
                                color: AppTheme.primaryColor,
                                size: 16,
                                semanticLabel: 'Bookmarked chapter',
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        ref
                            .read(readerJumpProvider(catalog.bookId).notifier)
                            .jumpToChapter(i);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});
  static const _lineHeights = [
    ('Compact', 1.3),
    ('Standard', 1.45),
    ('Relaxed', 1.6),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final spacing = _lineHeights
        .reduce(
          (a, b) =>
              (a.$2 - settings.lineHeight).abs() <
                  (b.$2 - settings.lineHeight).abs()
              ? a
              : b,
        )
        .$2;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHeading('Reading settings', fontSize: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Column(
                children: [
                  const _BrightnessControls(),
                  const SizedBox(height: 6),
                  _SettingRow(
                    label: 'Text size',
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: settings.controlColor,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                              ),
                              onPressed:
                                  settings.fontSize > ReaderSettings.minFontSize
                                  ? () => notifier.update(
                                      (s) => s.copyWith(
                                        fontSize: (s.fontSize - 1).clamp(
                                          ReaderSettings.minFontSize,
                                          ReaderSettings.maxFontSize,
                                        ),
                                      ),
                                    )
                                  : null,
                              child: const Text(
                                'A−',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              settings.fontSize.round().toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                              ),
                              onPressed:
                                  settings.fontSize < ReaderSettings.maxFontSize
                                  ? () => notifier.update(
                                      (s) => s.copyWith(
                                        fontSize: (s.fontSize + 1).clamp(
                                          ReaderSettings.minFontSize,
                                          ReaderSettings.maxFontSize,
                                        ),
                                      ),
                                    )
                                  : null,
                              child: const Text(
                                'A+',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _SettingRow(
                    label: 'Line spacing',
                    child: _Options<double>(
                      options: [
                        for (final (label, height) in _lineHeights)
                          (label, height),
                      ],
                      selected: spacing,
                      onChanged: (height) => notifier.update(
                        (s) => s.copyWith(lineHeight: height),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _SettingRow(
                    label: 'Page turning',
                    child: _Options<ReaderMode>(
                      options: const [
                        ('Scroll', ReaderMode.scroll),
                        ('Flip', ReaderMode.paged),
                      ],
                      selected: settings.mode,
                      onChanged: (mode) =>
                          notifier.update((s) => s.copyWith(mode: mode)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _SettingRow(
                    label: 'Background',
                    child: SizedBox(
                      height: 42,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final background in ReaderBackground.values)
                            Expanded(
                              child: Center(
                                child: Semantics(
                                  selected: settings.background == background,
                                  child: Tooltip(
                                    message: '${background.label} background',
                                    child: InkResponse(
                                      key: ValueKey(
                                        'background-${background.name}',
                                      ),
                                      radius: 26,
                                      onTap: () => notifier.update(
                                        (s) =>
                                            s.copyWith(background: background),
                                      ),
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            width: 2,
                                            color:
                                                settings.background ==
                                                    background
                                                ? AppTheme.primaryColor
                                                : Colors.transparent,
                                          ),
                                        ),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: background.color,
                                            border: Border.all(
                                              color: const Color(0xFFCFC4DA),
                                            ),
                                          ),
                                          child:
                                              settings.background == background
                                              ? Icon(
                                                  Icons.check,
                                                  size: 17,
                                                  color: background.textColor,
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
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
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 42),
    child: Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _Options<T> extends ConsumerWidget {
  const _Options({
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final List<(String, T)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: settings.controlColor,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          for (final (label, value) in options)
            Expanded(
              child: TextButton(
                onPressed: () => onChanged(value),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: value == selected
                      ? settings.selectedControlColor
                      : Colors.transparent,
                  foregroundColor: value == selected
                      ? settings.isNightMode
                            ? const Color(0xFFD4B5F4)
                            : const Color(0xFF7541A5)
                      : settings.secondaryTextColor,
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 12,
                    fontWeight: value == selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrightnessControls extends ConsumerWidget {
  const _BrightnessControls();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = ref.watch(readerBrightnessProvider);
    final notifier = ref.read(readerBrightnessProvider.notifier);
    return Column(
      children: [
        _SettingRow(
          label: 'Brightness',
          child: Row(
            children: [
              const Icon(Icons.brightness_low, size: 12),
              Expanded(
                child: Slider(
                  min: 0.05,
                  max: 1,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  value: brightness.value ?? 0.5,
                  semanticFormatterCallback: (value) =>
                      'Reading brightness ${(value * 100).round()}%',
                  onChanged: brightness.available
                      ? notifier.setBrightness
                      : null,
                ),
              ),
              const Icon(Icons.brightness_high, size: 16),
              const SizedBox(width: 6),
              SizedBox(
                width: 36,
                child: Text(
                  brightness.value == null
                      ? '—'
                      : '${(brightness.value! * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        if (brightness.error != null)
          Text(
            brightness.error!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}
