import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const primaryColor = Color(0xFF8051C9);
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      brightness: brightness,
    ),
  );
}
