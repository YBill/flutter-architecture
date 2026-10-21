/// Errors crossing infrastructure boundaries. UI code chooses localized copy.
abstract class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class ConfigurationException extends AppException {
  const ConfigurationException(super.message);
}

final class DataFormatException extends AppException {
  const DataFormatException(super.message, {super.cause});
}
