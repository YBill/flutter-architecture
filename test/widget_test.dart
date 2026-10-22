import 'features/reader/helpers/reader_test_support.dart';

import 'package:novelverse/features/books/application/book_providers.dart';
import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/app/app.dart';
import 'package:novelverse/app/startup_failure_app.dart';
import 'package:novelverse/l10n/app_localizations.dart';
import 'package:novelverse/app/router/app_router.dart';
import 'package:novelverse/app/settings/settings_controller.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets(
    'app stays English on a Chinese device and applies theme changes',
    (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final container = ProviderContainer(
        overrides: [
          ...readerTestOverrides(),
          bookApiProvider.overrideWithValue(MockBookApi(delay: Duration.zero)),
          bookCacheProvider.overrideWithValue(MemoryBookCache()),
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
      expect(find.text('Claimed By The Ruthless Alpha'), findsWidgets);

      final settings = container.read(settingsControllerProvider.notifier);
      await settings.setThemeMode(ThemeMode.dark);
      container.read(appRouterProvider).go('/missing');
      await tester.pumpAndSettle();
      expect(find.text('Page not found'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );

      expect(
        Localizations.localeOf(tester.element(find.byType(Scaffold))),
        const Locale('en'),
      );
      expect(AppLocalizations.supportedLocales, [const Locale('en')]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('device locale changes cannot switch the app language', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final container = ProviderContainer(
      overrides: [
        ...readerTestOverrides(),
        bookApiProvider.overrideWithValue(MockBookApi(delay: Duration.zero)),
        bookCacheProvider.overrideWithValue(MemoryBookCache()),
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
    expect(find.text('Page not found'), findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(find.byType(Scaffold))),
      const Locale('en'),
    );
  });

  testWidgets('startup failure also stays English on a Chinese device', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(StartupFailureApp(onRetry: () async {}));
    expect(
      find.text('Unable to start the app. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(find.byType(Scaffold))),
      const Locale('en'),
    );
  });
}
