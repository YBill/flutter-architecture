import 'package:flutter/painting.dart';

enum ReaderMode { paged, scroll }

class ReaderSettings {
  const ReaderSettings({
    required this.fontSize,
    required this.lineHeight,
    required this.mode,
    this.isNightMode = false,
  });

  final double fontSize;
  final double lineHeight;
  final ReaderMode mode;
  final bool isNightMode;

  Color get backgroundColor =>
      isNightMode ? const Color(0xFF171A1F) : const Color(0xFFF7F4EC);
  Color get surfaceColor =>
      isNightMode ? const Color(0xFF23272E) : const Color(0xFFFFFFFF);
  Color get textColor =>
      isNightMode ? const Color(0xFFCDD1D7) : const Color(0xFF262626);
  Color get secondaryTextColor =>
      isNightMode ? const Color(0xFF9299A3) : const Color(0x66000000);

  static const minFontSize = 14.0;
  static const maxFontSize = 28.0;

  // inherit:false — Text 会把 DefaultTextStyle（Roboto/letterSpacing）merge 进 inherit=true
  // 的样式，导致渲染断行与分页测量（裸样式 TextPainter）不一致、页尾截行。
  TextStyle get textStyle => TextStyle(
    inherit: false,
    fontSize: fontSize,
    height: lineHeight,
    color: textColor,
  );

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderMode? mode,
    bool? isNightMode,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      mode: mode ?? this.mode,
      isNightMode: isNightMode ?? this.isNightMode,
    );
  }
}
