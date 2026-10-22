import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/core/logging/app_logger.dart';
import 'package:novelverse/core/storage/preferences_store.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('text size, spacing, page turning and background survive a fresh app container', () async {
    final store = PreferencesStore(namespace: 'reader-test.');
    final logger = AppLogger(release: true);
    final container = ProviderContainer();
    final notifier = container.read(readerSettingsProvider.notifier);
    await notifier.initialize(store, logger);
    notifier.update((s) => s.copyWith(fontSize: 23));
    notifier.update((s) => s.copyWith(lineHeight: 1.6));
    notifier.update((s) => s.copyWith(mode: ReaderMode.scroll));
    notifier.update((s) => s.copyWith(background: ReaderBackground.green));
    Map<String, dynamic>? saved;
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      final value = await store.getString('reader_settings');
      if (value != null) saved = jsonDecode(value) as Map<String, dynamic>;
      if (saved?['background'] == 'green') break;
    }
    expect(
      saved,
      {
        'fontSize': 23,
        'lineHeight': 1.6,
        'mode': 'scroll',
        'background': 'green',
      },
      reason:
          'Only durable reader settings belong in SP; brightness is per visit.',
    );
    container.dispose();

    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    await restarted
        .read(readerSettingsProvider.notifier)
        .initialize(store, logger);
    final settings = restarted.read(readerSettingsProvider);
    expect(settings.fontSize, 23);
    expect(settings.lineHeight, 1.6);
    expect(settings.mode, ReaderMode.scroll);
    expect(settings.background, ReaderBackground.green);
  });

  test('legacy night preference restores, and all five palettes persist after reopening', () async {
    final store = PreferencesStore(namespace: 'reader-test.');
    final logger = AppLogger(release: true);
    await store.setString('reader_settings', jsonEncode({'isNightMode': true}));
    var container = ProviderContainer();
    await container
        .read(readerSettingsProvider.notifier)
        .initialize(store, logger);
    expect(
      container.read(readerSettingsProvider).background,
      ReaderBackground.dark,
    );
    container.dispose();

    for (final background in ReaderBackground.values) {
      container = ProviderContainer();
      final notifier = container.read(readerSettingsProvider.notifier);
      await notifier.initialize(store, logger);
      notifier.update((s) => s.copyWith(background: background));
      // Wait for the asynchronous preferences write, without recreating its store.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
        final saved =
            jsonDecode((await store.getString('reader_settings'))!) as Map;
        if (saved['background'] == background.name) break;
      }
      container.dispose();
      final restored = ProviderContainer();
      await restored
          .read(readerSettingsProvider.notifier)
          .initialize(store, logger);
      expect(restored.read(readerSettingsProvider).background, background);
      expect(
        restored.read(readerSettingsProvider).isNightMode,
        background == ReaderBackground.dark,
      );
      restored.dispose();
    }
  });
}
