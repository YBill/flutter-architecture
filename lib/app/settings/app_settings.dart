import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

part 'app_settings.g.dart';

@JsonSerializable(checked: true)
final class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.system});

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);

  @JsonKey(unknownEnumValue: ThemeMode.system)
  final ThemeMode themeMode;

  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);

  AppSettings withThemeMode(ThemeMode value) => AppSettings(themeMode: value);
}
