import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import '../../core/logging/app_logger.dart';
import '../../core/storage/preferences_store.dart';
import 'app_settings.dart';

final class SettingsRepository {
  SettingsRepository(this._preferences, this._logger);

  static const _key = 'app_settings';
  final PreferencesStore _preferences;
  final AppLogger _logger;

  Future<AppSettings> load() async {
    // Read failures are startup failures; only malformed content falls back.
    final stored = await _preferences.getString(_key);
    if (stored == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(stored) as Map<String, dynamic>);
    } on FormatException {
      _logger.warning('Ignoring malformed app settings.');
    } on TypeError {
      _logger.warning('Ignoring invalid app settings types.');
    } on CheckedFromJsonException {
      _logger.warning('Ignoring invalid app settings fields.');
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) =>
      _preferences.setString(_key, jsonEncode(settings.toJson()));
}
