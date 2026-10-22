import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/providers/core_providers.dart';
import 'app_settings.dart';
import 'settings_repository.dart';

part 'settings_controller.g.dart';

@Riverpod(keepAlive: true)
AppSettings initialAppSettings(Ref ref) =>
    throw StateError('Override initialAppSettingsProvider during bootstrap.');

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) => SettingsRepository(
  ref.watch(preferencesStoreProvider),
  ref.watch(appLoggerProvider),
);

@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  Future<void> _pending = Future<void>.value();

  @override
  AppSettings build() => ref.watch(initialAppSettingsProvider);

  Future<void> setThemeMode(ThemeMode mode) =>
      _update((settings) => settings.withThemeMode(mode));

  Future<void> _update(AppSettings Function(AppSettings) update) {
    // Serialize changes so a slower earlier write cannot overwrite a later one.
    final operation = _pending.then((_) async {
      if (!ref.mounted) return;
      final next = update(state);
      await ref.read(settingsRepositoryProvider).save(next);
      if (ref.mounted) state = next;
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }
}
