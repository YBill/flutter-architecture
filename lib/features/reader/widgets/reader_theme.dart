import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../state/reader_providers.dart';

/// Reader palettes also wrap modal routes so an open sheet updates immediately.
class ReaderTheme extends ConsumerWidget {
  const ReaderTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final night = settings.isNightMode;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppTheme.primaryColor,
      brightness: night ? Brightness.dark : Brightness.light,
      primary: AppTheme.primaryColor,
      surface: settings.surfaceColor,
      onSurface: settings.textColor,
    );
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: settings.backgroundColor,
        dividerColor: settings.dividerColor,
        iconTheme: IconThemeData(color: settings.textColor),
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: settings.textColor,
          displayColor: settings.textColor,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppTheme.primaryColor,
          thumbColor: AppTheme.primaryColor,
          inactiveTrackColor: settings.selectedControlColor,
          trackHeight: 6,
        ),
      ),
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
        child: Material(color: settings.surfaceColor, child: child),
      ),
    );
  }
}
