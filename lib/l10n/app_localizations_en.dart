// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NovaNovel';

  @override
  String get pageNotFound => 'Page not found';

  @override
  String get startupFailed => 'Unable to start the app. Please try again.';

  @override
  String get retry => 'Retry';

  @override
  String get chapterPreview => 'CHAPTER PREVIEW';

  @override
  String get continueReading => 'Continue Reading';

  @override
  String get readMore => 'Read more';

  @override
  String get showLess => 'Show less';

  @override
  String get startFreeReading => 'Start Free Reading';

  @override
  String get youMightLike => 'You Might Be Like';

  @override
  String get library => 'Library';

  @override
  String get saved => 'Saved';

  @override
  String get readers => 'Readers';

  @override
  String get savedReaders => 'Saved';

  @override
  String get rating => 'Rating';

  @override
  String get completed => 'Completed';

  @override
  String get shareBook => 'Share book';

  @override
  String get bookLoadFailed => 'Could not load this book.';

  @override
  String get recommendationsFailed => 'Could not load recommendations. Retry';

  @override
  String get actionFailed => 'Something went wrong. Please try again.';

  @override
  String chapterCount(int count) {
    return '$count chapters';
  }
}
