import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/core/config/app_config.dart';

void main() {
  test('plain debug launch connects to the local API by default', () {
    final config = AppConfig.fromEnvironment();
    expect(config.environment, AppEnvironment.dev);
    expect(config.apiBaseUri.toString(), 'http://127.0.0.1:8787/api/v1/');
    expect(config.enableHttpLogging, isTrue);
  });

  test('supports starting before the backend is configured', () {
    final config = AppConfig.fromValues();
    expect(config.environment, AppEnvironment.dev);
    expect(config.apiBaseUri, isNull);
  });

  test('normalizes the base URL without losing its path', () {
    final config = AppConfig.fromValues(apiBaseUrl: 'https://example.test/v1');
    expect(config.apiBaseUri.toString(), 'https://example.test/v1/');
  });

  test('rejects invalid or ambiguous configuration', () {
    expect(
      () => AppConfig.fromValues(environment: 'production'),
      throwsArgumentError,
    );
    for (final value in [
      '/v1',
      'ftp://example.test',
      'https://user:password@example.test',
      'https://example.test?token=value',
      'https://example.test#fragment',
    ]) {
      expect(
        () => AppConfig.fromValues(apiBaseUrl: value),
        throwsArgumentError,
      );
    }
  });

  test('production disables HTTP logging and isolates storage', () {
    final dev = AppConfig.fromValues();
    final prod = AppConfig.fromValues(
      environment: 'prod',
      enableHttpLogging: true,
    );
    expect(prod.enableHttpLogging, isFalse);
    expect(prod.storageNamespace, isNot(dev.storageNamespace));
    expect(prod.databaseName, isNot(dev.databaseName));
  });
}
