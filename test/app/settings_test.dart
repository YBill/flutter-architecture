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

  test('settings JSON round trips a script-specific locale', () {
    const settings = AppSettings(
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      themeMode: ThemeMode.dark,
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.locale, settings.locale);
    expect(restored.themeMode, ThemeMode.dark);
  });

  test('old or unsupported locale/theme values follow the system', () {
    final settings = AppSettings.fromJson({
      'locale': 'unsupported',
      'themeMode': 'old_theme_value',
    });
    expect(settings.locale, isNull);
    expect(settings.themeMode, ThemeMode.system);
  });

  test(
    'concurrent settings changes preserve both values after restart',
    () async {
      final controller = container.read(settingsControllerProvider.notifier);
      await Future.wait([
        controller.setLocale(const Locale('zh')),
        controller.setThemeMode(ThemeMode.dark),
      ]);
      final restored = await SettingsRepository(
        PreferencesStore(namespace: 'test.'),
        AppLogger(release: true),
      ).load();
      expect(restored.locale, const Locale('zh'));
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

  test('resetting locale persists follow-system mode', () async {
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.setLocale(const Locale('en'));
    await controller.setLocale(null);
    expect((await repository.load()).locale, isNull);
  });

  test(
    'malformed saved settings fall back, but platform failures propagate',
    () async {
      for (final value in ['{', '[]', '{"locale":42}']) {
        await preferences.setString('app_settings', value);
        expect((await repository.load()).themeMode, ThemeMode.system);
      }
      platform.failReads = true;
      await expectLater(repository.load(), throwsStateError);
    },
  );
}
