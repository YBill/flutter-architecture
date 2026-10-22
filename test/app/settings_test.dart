import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/app/settings/app_settings.dart';
import 'package:novelverse/app/settings/settings_controller.dart';
import 'package:novelverse/app/settings/settings_repository.dart';
import 'package:novelverse/core/logging/app_logger.dart';
import 'package:novelverse/core/providers/core_providers.dart';
import 'package:novelverse/core/storage/preferences_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

final class FailingPreferencesPlatform extends InMemorySharedPreferencesAsync {
  FailingPreferencesPlatform() : super.empty();

  bool failWrites = false;
  bool failReads = false;

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) {
    if (failWrites) throw StateError('Storage unavailable.');
    return super.setString(key, value, options);
  }

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) {
    if (failReads) throw StateError('Storage unavailable.');
    return super.getString(key, options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FailingPreferencesPlatform platform;
  late PreferencesStore preferences;
  late SettingsRepository repository;
  late ProviderContainer container;

  setUp(() {
    platform = FailingPreferencesPlatform();
    SharedPreferencesAsyncPlatform.instance = platform;
    preferences = PreferencesStore(namespace: 'test.');
    final logger = AppLogger(release: true);
    repository = SettingsRepository(preferences, logger);
    container = ProviderContainer(
      retry: (count, error) => null,
      overrides: [
        preferencesStoreProvider.overrideWithValue(preferences),
        appLoggerProvider.overrideWithValue(logger),
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
      ],
    );
  });
  tearDown(() => container.dispose());

  test('settings JSON round trips the theme', () {
    const settings = AppSettings(themeMode: ThemeMode.dark);
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.toJson(), {'themeMode': 'dark'});
  });

  test('legacy locale is ignored while the saved theme is retained', () async {
    await preferences.setString(
      'app_settings',
      '{"locale":"zh-Hant","themeMode":"dark"}',
    );
    final settings = await repository.load();
    expect(settings.themeMode, ThemeMode.dark);
    await repository.save(settings);
    expect(await preferences.getString('app_settings'), '{"themeMode":"dark"}');
  });

  test('unsupported theme values follow the system', () {
    final settings = AppSettings.fromJson({'themeMode': 'old_theme_value'});
    expect(settings.themeMode, ThemeMode.system);
  });

  test(
    'concurrent theme changes preserve the latest value after restart',
    () async {
      final controller = container.read(settingsControllerProvider.notifier);
      await Future.wait([
        controller.setThemeMode(ThemeMode.light),
        controller.setThemeMode(ThemeMode.dark),
      ]);
      final restored = await SettingsRepository(
        PreferencesStore(namespace: 'test.'),
        AppLogger(release: true),
      ).load();
      expect(restored.themeMode, ThemeMode.dark);
      expect(
        container.read(settingsControllerProvider).themeMode,
        ThemeMode.dark,
      );
    },
  );

  test(
    'failed writes propagate, preserve state and do not break later writes',
    () async {
      final controller = container.read(settingsControllerProvider.notifier);
      platform.failWrites = true;
      await expectLater(
        controller.setThemeMode(ThemeMode.dark),
        throwsStateError,
      );
      expect(
        container.read(settingsControllerProvider).themeMode,
        ThemeMode.system,
      );
      platform.failWrites = false;
      await controller.setThemeMode(ThemeMode.light);
      expect((await repository.load()).themeMode, ThemeMode.light);
    },
  );

  test(
    'malformed saved settings fall back, but platform failures propagate',
    () async {
      for (final value in ['{', '[]', '{"themeMode":42}']) {
        await preferences.setString('app_settings', value);
        expect((await repository.load()).themeMode, ThemeMode.system);
      }
      platform.failReads = true;
      await expectLater(repository.load(), throwsStateError);
    },
  );
}
