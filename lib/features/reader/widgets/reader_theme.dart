import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/reader_settings.dart';
import '../state/reader_providers.dart';

/// Reader palettes also wrap modal routes so an open sheet updates immediately.
class ReaderTheme extends ConsumerStatefulWidget {
  const ReaderTheme({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReaderTheme> createState() => _ReaderThemeState();
}

class _ReaderThemeState extends ConsumerState<ReaderTheme> {
  ThemeData? _baseTheme;
  ReaderBackground? _background;
  ThemeData? _theme;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final night = settings.isNightMode;
    final base = Theme.of(context);
    if (_baseTheme != base || _background != settings.background) {
      _baseTheme = base;
      _background = settings.background;
      final scheme = ColorScheme.fromSeed(
        seedColor: AppTheme.primaryColor,
        brightness: night ? Brightness.dark : Brightness.light,
        primary: AppTheme.primaryColor,
        surface: settings.surfaceColor,
        onSurface: settings.textColor,
      );
      _theme = base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: settings.backgroundColor,
        dividerColor: settings.dividerColor,
        iconTheme: IconThemeData(color: settings.textColor),
        textTheme: base.textTheme.apply(
          bodyColor: settings.textColor,
          displayColor: settings.textColor,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppTheme.primaryColor,
          thumbColor: AppTheme.primaryColor,
          inactiveTrackColor: settings.selectedControlColor,
          trackHeight: 6,
        ),
      );
    }
    return Theme(
      data: _theme!,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: (night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: settings.backgroundColor,
              systemNavigationBarIconBrightness: night
                  ? Brightness.light
                  : Brightness.dark,
              systemStatusBarContrastEnforced: false,
              systemNavigationBarContrastEnforced: false,
            ),
        child: Material(color: settings.surfaceColor, child: widget.child),
      ),
    );
  }
}
