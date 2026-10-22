import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'theme/app_theme.dart';

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.startupFailed),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => unawaited(onRetry()),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
