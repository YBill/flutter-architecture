import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/providers/core_providers.dart';
import '../core/storage/preferences_store.dart';
import 'app.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_repository.dart';
import 'startup_failure_app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = AppLogger(
    release: kReleaseMode || const String.fromEnvironment('APP_ENV') == 'prod',
  );
  FlutterError.onError = (details) {
    logger.error(
      'Flutter framework error.',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    logger.error(
      'Unhandled async error.',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };

  try {
    final config = AppConfig.fromEnvironment();
    final preferences = PreferencesStore(namespace: config.storageNamespace);
    final settings = await SettingsRepository(preferences, logger).load();
    runApp(
      ProviderScope(
        // Reads can opt into bounded retries later. Never repeat writes here.
        retry: (retryCount, error) => null,
        overrides: [
          appConfigProvider.overrideWithValue(config),
          appLoggerProvider.overrideWithValue(logger),
          preferencesStoreProvider.overrideWithValue(preferences),
          initialAppSettingsProvider.overrideWithValue(settings),
        ],
        child: const NovelverseApp(),
      ),
    );
  } catch (error, stackTrace) {
    logger.error('App startup failed.', error: error, stackTrace: stackTrace);
    runApp(StartupFailureApp(onRetry: bootstrap));
  }
}
