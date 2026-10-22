import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../books/domain/book.dart';
import '../domain/reader_settings.dart';
import '../state/reader_providers.dart';
import '../state/reader_brightness_provider.dart';
import 'reader_theme.dart';

class ReaderTopBar extends ConsumerWidget {
  const ReaderTopBar({super.key, required this.chapterTitle});

  final String chapterTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Back to book',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class ReaderBottomBar extends ConsumerWidget {
  const ReaderBottomBar({super.key, required this.catalog});

  final BookCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterIndex = ref.watch(
      readerPositionProvider(catalog.bookId).select((p) => p.chapterIndex),
    );
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MenuAction(
                onPressed: () => _showCatalog(context, ref),
                icon: Icons.menu_book_outlined,
                label: 'Chapters',
              ),
              _MenuAction(
                onPressed: chapterIndex > 0
                    ? () => ref
                          .read(readerJumpProvider(catalog.bookId).notifier)
                          .jumpToChapter(chapterIndex - 1)
                    : null,
                icon: Icons.skip_previous_outlined,
                label: 'Previous',
              ),
              _MenuAction(
                onPressed: chapterIndex < catalog.chapters.length - 1
                    ? () => ref
                          .read(readerJumpProvider(catalog.bookId).notifier)
                          .jumpToChapter(chapterIndex + 1)
                    : null,
                icon: Icons.skip_next_outlined,
                label: 'Next',
              ),
              _MenuAction(
                onPressed: () => _showSettings(context, ref),
                icon: Icons.settings_outlined,
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCatalog(BuildContext context, WidgetRef ref) {
    final position = ref.read(readerPositionProvider(catalog.bookId));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      useSafeArea: true,
      builder: (_) => ReaderTheme(
        child: _CatalogSheet(
          catalog: catalog,
          currentChapter: position.chapterIndex,
        ),
      ),
    );
  }

  void _showSettings(BuildContext context, WidgetRef ref) {
    ref.read(readerBrightnessProvider.notifier).refresh();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const ReaderTheme(
        child: SingleChildScrollView(child: _SettingsSheet()),
      ),
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
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Expanded(
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _CatalogSheet extends ConsumerWidget {
  const _CatalogSheet({required this.catalog, required this.currentChapter});

  final BookCatalog catalog;
  final int currentChapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: SizedBox(
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chapters (${catalog.chapters.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ScrollablePositionedList.builder(
                initialScrollIndex: currentChapter,
                itemCount: catalog.chapters.length,
                itemBuilder: (context, i) {
                  final current = i == currentChapter;
                  return ListTile(
                    dense: true,
                    title: Text(
                      catalog.chapters[i].title,
                      style: TextStyle(
                        fontSize: 15,
                        color: current
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    onTap: () {
                      ref
                          .read(readerJumpProvider(catalog.bookId).notifier)
                          .jumpToChapter(i);
                      Navigator.of(context).pop();
                    },
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

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  static const _lineHeightOptions = [
    ('Compact', 1.3),
    ('Standard', 1.45),
    ('Relaxed', 1.6),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                settings.isNightMode ? Icons.dark_mode : Icons.light_mode,
              ),
              title: const Text('Night mode'),
              value: settings.isNightMode,
              onChanged: (value) =>
                  notifier.update((s) => s.copyWith(isNightMode: value)),
            ),
            const _BrightnessControls(),
            const SizedBox(height: 22),
            // 阅读模式
            const Text('Reading mode', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            SegmentedButton<ReaderMode>(
              segments: const [
                ButtonSegment(
                  value: ReaderMode.paged,
                  label: Text('Swipe pages'),
                  icon: Icon(Icons.swap_horiz),
                ),
                ButtonSegment(
                  value: ReaderMode.scroll,
                  label: Text('Scroll'),
                  icon: Icon(Icons.swap_vert),
                ),
              ],
              selected: {settings.mode},
              onSelectionChanged: (modes) =>
                  notifier.update((s) => s.copyWith(mode: modes.first)),
            ),
            const SizedBox(height: 22),
            // Font size
            const Text('Font size', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: settings.fontSize > ReaderSettings.minFontSize
                      ? () => notifier.update(
                          (s) => s.copyWith(
                            fontSize: (s.fontSize - 2).clamp(
                              ReaderSettings.minFontSize,
                              ReaderSettings.maxFontSize,
                            ),
                          ),
                        )
                      : null,
                  icon: const Text('A-', style: TextStyle(fontSize: 15)),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      settings.fontSize.round().toString(),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: settings.fontSize < ReaderSettings.maxFontSize
                      ? () => notifier.update(
                          (s) => s.copyWith(
                            fontSize: (s.fontSize + 2).clamp(
                              ReaderSettings.minFontSize,
                              ReaderSettings.maxFontSize,
                            ),
                          ),
                        )
                      : null,
                  icon: const Text('A+', style: TextStyle(fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 22),
            // Line spacing
            const Text('Line spacing', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                for (final (label, _) in _lineHeightOptions)
                  ButtonSegment(value: label, label: Text(label)),
              ],
              selected: {
                _lineHeightOptions
                    .firstWhere(
                      (o) => (o.$2 - settings.lineHeight).abs() < 0.01,
                      orElse: () => _lineHeightOptions[1],
                    )
                    .$1,
              },
              onSelectionChanged: (labels) {
                final value = _lineHeightOptions
                    .firstWhere((o) => o.$1 == labels.first)
                    .$2;
                notifier.update((s) => s.copyWith(lineHeight: value));
              },
            ),
          ],
        ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Brightness', style: TextStyle(fontSize: 13)),
            ),
            TextButton(
              onPressed: brightness.available && !brightness.followSystem
                  ? notifier.useSystemBrightness
                  : null,
              child: Text(
                brightness.followSystem ? 'Following system' : 'Use system',
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.brightness_low, size: 20),
            Expanded(
              child: Slider(
                min: 0.05,
                max: 1,
                value: brightness.value ?? 0.5,
                label: '${((brightness.value ?? 0.5) * 100).round()}%',
                semanticFormatterCallback: (value) =>
                    'Reading brightness ${(value * 100).round()}%',
                onChanged: brightness.available ? notifier.setBrightness : null,
              ),
            ),
            const Icon(Icons.brightness_high, size: 20),
          ],
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
