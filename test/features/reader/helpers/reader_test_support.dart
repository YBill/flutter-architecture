import 'dart:async';

import 'package:drift/native.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;
import 'package:novelverse/app/settings/app_settings.dart';
import 'package:novelverse/app/settings/settings_controller.dart';
import 'package:novelverse/core/config/app_config.dart';
import 'package:novelverse/core/database/app_database.dart';
import 'package:novelverse/core/database/database_providers.dart';
import 'package:novelverse/core/logging/app_logger.dart';
import 'package:novelverse/core/providers/core_providers.dart';
import 'package:novelverse/core/storage/preferences_store.dart';
import 'package:novelverse/features/books/application/book_providers.dart';
import 'package:novelverse/features/reader/data/reading_progress_store.dart';
import 'package:novelverse/features/reader/domain/reading_position.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class MemoryReadingProgressStore implements ReadingProgressStore {
  final values = <String, ReaderPosition>{};
  @override
  Future<ReaderPosition?> read(String bookId) async => values[bookId];
  @override
  Future<void> write(String bookId, ReaderPosition position) async {
    values[bookId] = position;
  }
}

List<Override> readerTestOverrides({ReadingProgressStore? progressStore}) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  return [
    appConfigProvider.overrideWithValue(AppConfig.fromValues()),
    appLoggerProvider.overrideWithValue(AppLogger(release: true)),
    preferencesStoreProvider.overrideWithValue(
      PreferencesStore(namespace: 'test.'),
    ),
    initialAppSettingsProvider.overrideWithValue(const AppSettings()),
    readingProgressStoreProvider.overrideWithValue(
      progressStore ?? MemoryReadingProgressStore(),
    ),
    appDatabaseProvider.overrideWith((ref) {
      final database = AppDatabase(NativeDatabase.memory());
      ref.onDispose(() => unawaited(database.close()));
      return database;
    }),
  ];
}
