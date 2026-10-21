import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/core_providers.dart';
import 'app_database.dart';

part 'database_providers.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final database = AppDatabase.open(
    name: ref.watch(appConfigProvider).databaseName,
  );
  ref.onDispose(() => unawaited(database.close()));
  return database;
}
