enum AppEnvironment { dev, staging, prod }

/// Compile-time configuration. Values in the app bundle are not secrets.
final class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.apiBaseUri,
    required this.enableHttpLogging,
  });

  factory AppConfig.fromEnvironment() => AppConfig.fromValues(
    environment: const String.fromEnvironment('APP_ENV', defaultValue: 'dev'),
    apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
    enableHttpLogging: const bool.fromEnvironment('HTTP_LOG_ENABLED'),
  );

  factory AppConfig.fromValues({
    String environment = 'dev',
    String apiBaseUrl = '',
    bool enableHttpLogging = false,
  }) {
    final appEnvironment = AppEnvironment.values.byName(environment);
    final rawUrl = apiBaseUrl.trim();
    Uri? baseUri;
    if (rawUrl.isNotEmpty) {
      final uri = Uri.tryParse(rawUrl);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw ArgumentError('API_BASE_URL must be an HTTP(S) base URL.');
      }
      baseUri = uri.replace(
        path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
      );
    }
    return AppConfig._(
      environment: appEnvironment,
      apiBaseUri: baseUri,
      enableHttpLogging:
          enableHttpLogging && appEnvironment != AppEnvironment.prod,
    );
  }

  final AppEnvironment environment;
  final Uri? apiBaseUri;
  final bool enableHttpLogging;

  String get storageNamespace => 'novelverse.${environment.name}.';
  String get databaseName => 'novelverse_${environment.name}';
}
