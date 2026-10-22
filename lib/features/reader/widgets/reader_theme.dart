import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/reader_providers.dart';

/// 只包住阅读页及其弹层，不改变首页或整个应用的主题。
class ReaderTheme extends ConsumerWidget {
  const ReaderTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(
      readerSettingsProvider.select((s) => s.isNightMode),
    );
    final settings = ref.read(readerSettingsProvider);
    final overlay =
        (night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: settings.backgroundColor,
              systemNavigationBarIconBrightness: night
                  ? Brightness.light
                  : Brightness.dark,
            );
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: settings.backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8623D),
          brightness: night ? Brightness.dark : Brightness.light,
          surface: settings.surfaceColor,
        ),
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Material(color: settings.surfaceColor, child: child),
      ),
    );
  }
}
