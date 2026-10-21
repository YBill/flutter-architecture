import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../storage/preferences_store.dart';
import '../storage/secure_store.dart';

part 'core_providers.g.dart';

@Riverpod(keepAlive: true)
AppConfig appConfig(Ref ref) =>
    throw StateError('Override appConfigProvider during bootstrap.');

@Riverpod(keepAlive: true)
AppLogger appLogger(Ref ref) =>
    throw StateError('Override appLoggerProvider during bootstrap.');

@Riverpod(keepAlive: true)
PreferencesStore preferencesStore(Ref ref) =>
    PreferencesStore(namespace: ref.watch(appConfigProvider).storageNamespace);

@Riverpod(keepAlive: true)
SecureStore secureStore(Ref ref) =>
    SecureStore(namespace: ref.watch(appConfigProvider).storageNamespace);
