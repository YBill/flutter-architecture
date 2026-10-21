// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Novelverse';

  @override
  String get pageNotFound => 'Page not found';

  @override
  String get startupFailed => 'Unable to start the app. Please try again.';

  @override
  String get retry => 'Retry';
}
