import 'package:logger/logger.dart';

/// The single logging entry point. Never pass credentials or raw user content.
final class AppLogger {
  AppLogger({bool release = false, LogOutput? output})
    : _logger = Logger(
        filter: ProductionFilter(),
        level: release ? Level.warning : Level.debug,
        printer: SimplePrinter(printTime: true, colors: false),
        output: output,
      );

  final Logger _logger;

  void debug(String message) => _logger.d(message);
  void info(String message) => _logger.i(message);
  void warning(String message) => _logger.w(message);
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(message, error: error, stackTrace: stackTrace);
}
