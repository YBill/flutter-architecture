import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/app/app.dart';
import 'package:novelverse/app/router/app_router.dart';
import 'package:novelverse/app/settings/app_settings.dart';
import 'package:novelverse/app/settings/settings_controller.dart';
import 'package:novelverse/core/logging/app_logger.dart';
import 'package:novelverse/core/providers/core_providers.dart';
import 'package:novelverse/core/storage/preferences_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('app boots and applies persisted locale and theme changes', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
        preferencesStoreProvider.overrideWithValue(
          PreferencesStore(namespace: 'test.'),
        ),
        appLoggerProvider.overrideWithValue(AppLogger(release: true)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NovelverseApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Novelverse'), findsOneWidget);

    final settings = container.read(settingsControllerProvider.notifier);
    await settings.setLocale(const Locale('zh'));
    await settings.setThemeMode(ThemeMode.dark);
    container.read(appRouterProvider).go('/missing');
    await tester.pumpAndSettle();
    expect(find.text('页面不存在'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );

    await settings.setLocale(
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    await tester.pumpAndSettle();
    expect(find.text('頁面不存在'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('follow-system mode responds to device locale changes', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NovelverseApp(),
      ),
    );
    container.read(appRouterProvider).go('/missing');
    await tester.pumpAndSettle();
    expect(find.text('Page not found'), findsOneWidget);

    tester.platformDispatcher.localesTestValue = [const Locale('zh')];
    await tester.pumpAndSettle();
    expect(find.text('页面不存在'), findsOneWidget);
  });
}
