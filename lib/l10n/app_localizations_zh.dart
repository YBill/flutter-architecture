// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Novelverse';

  @override
  String get pageNotFound => '页面不存在';

  @override
  String get startupFailed => '应用暂时无法启动，请重试。';

  @override
  String get retry => '重试';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => 'Novelverse';

  @override
  String get pageNotFound => '頁面不存在';

  @override
  String get startupFailed => '應用程式暫時無法啟動，請重試。';

  @override
  String get retry => '重試';
}
