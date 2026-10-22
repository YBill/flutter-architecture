import 'package:flutter/painting.dart';

enum ReaderMode { paged, scroll }

enum ReaderBackground {
  paper('Paper', Color(0xFFFFFDFA), Color(0xFF292231)),
  cream('Cream', Color(0xFFF4EFD9), Color(0xFF393527)),
  green('Green', Color(0xFFE8F1EC), Color(0xFF283C32)),
  blue('Blue', Color(0xFFE7EFF4), Color(0xFF293B4A)),
  dark('Night', Color(0xFF18151E), Color(0xFFE8DFEF));

  const ReaderBackground(this.label, this.color, this.textColor);
  final String label;
  final Color color;
  final Color textColor;
}

class ReaderSettings {
  const ReaderSettings({
    required this.fontSize,
    required this.lineHeight,
    required this.mode,
    ReaderBackground background = ReaderBackground.paper,
    bool isNightMode = false,
  }) : background = isNightMode ? ReaderBackground.dark : background;

  final double fontSize;
  final double lineHeight;
  final ReaderMode mode;
  final ReaderBackground background;
  bool get isNightMode => background == ReaderBackground.dark;

  Color get backgroundColor => background.color;
  Color get surfaceColor => backgroundColor;
  Color get textColor => background.textColor;
  Color get secondaryTextColor =>
      isNightMode ? const Color(0xFFB0A3BF) : const Color(0xFF8C7B99);
  Color get controlColor =>
      isNightMode ? const Color(0xFF292332) : const Color(0xFFF2ECF8);
  Color get selectedControlColor =>
      isNightMode ? const Color(0xFF48305F) : const Color(0xFFE2CFF0);
  Color get dividerColor =>
      isNightMode ? const Color(0xFF36303F) : const Color(0xFFEDE5F2);

  static const minFontSize = 14.0;
  static const maxFontSize = 28.0;
  static const serifFontFamily = 'Georgia';
  static const serifFontFallback = ['Noto Serif', 'Times New Roman', 'serif'];

  // Keep the renderer and TextPainter identical, including the font family.
  TextStyle get textStyle => TextStyle(
    inherit: false,
    fontFamily: serifFontFamily,
    fontFamilyFallback: serifFontFallback,
    fontSize: fontSize,
    height: lineHeight,
    color: textColor,
  );

  TextStyle get titleStyle => textStyle.copyWith(
    fontSize: fontSize * 1.5,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderMode? mode,
    ReaderBackground? background,
    bool? isNightMode,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    mode: mode ?? this.mode,
    background:
        background ??
        (isNightMode == null
            ? this.background
            : isNightMode
            ? ReaderBackground.dark
            : ReaderBackground.paper),
  );
}
