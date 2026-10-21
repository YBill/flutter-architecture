import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../l10n/app_localizations.dart';

part 'app_settings.g.dart';

@JsonSerializable(checked: true)
final class AppSettings {
  const AppSettings({this.locale, this.themeMode = ThemeMode.system});

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);

  @JsonKey(fromJson: _localeFromJson, toJson: _localeToJson)
  final Locale? locale;

  @JsonKey(unknownEnumValue: ThemeMode.system)
  final ThemeMode themeMode;

  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);

  AppSettings withLocale(Locale? value) =>
      AppSettings(locale: value, themeMode: themeMode);

  AppSettings withThemeMode(ThemeMode value) =>
      AppSettings(locale: locale, themeMode: value);
}

Locale? _localeFromJson(String? tag) {
  for (final locale in AppLocalizations.supportedLocales) {
    if (locale.toLanguageTag() == tag) return locale;
  }
  return null;
}

String? _localeToJson(Locale? locale) => locale?.toLanguageTag();
