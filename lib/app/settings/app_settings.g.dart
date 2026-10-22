// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AppSettings', json, ($checkedConvert) {
      final val = AppSettings(
        themeMode: $checkedConvert(
          'themeMode',
          (v) =>
              $enumDecodeNullable(
                _$ThemeModeEnumMap,
                v,
                unknownValue: ThemeMode.system,
              ) ??
              ThemeMode.system,
        ),
      );
      return val;
    });

Map<String, dynamic> _$AppSettingsToJson(AppSettings instance) =>
    <String, dynamic>{'themeMode': _$ThemeModeEnumMap[instance.themeMode]!};

const _$ThemeModeEnumMap = {
  ThemeMode.system: 'system',
  ThemeMode.light: 'light',
  ThemeMode.dark: 'dark',
};
