import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:novelverse/core/config/app_config.dart';
import 'package:novelverse/core/logging/app_logger.dart';
import 'package:novelverse/core/network/network_log_interceptor.dart';
import 'package:novelverse/core/network/network_providers.dart';
import 'package:novelverse/core/providers/core_providers.dart';

import '../../support/stub_http_adapter.dart';

final class CapturedOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

void main() {
  test(
    'network logs exclude header, query, request and response values',
    () async {
      final output = CapturedOutput();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      addTearDown(() => dio.close(force: true));
      dio.interceptors.add(NetworkLogInterceptor(AppLogger(output: output)));
      dio.httpClientAdapter = StubHttpAdapter(
        (_) async => jsonResponse('{"secret":"response-secret"}'),
      );
      await dio.post<Object?>(
        '/status',
        queryParameters: {'token': 'query-secret'},
        data: {'password': 'body-secret'},
        options: Options(headers: {'Authorization': 'header-secret'}),
      );
      final logs = output.lines.join('\n');
      expect(logs, contains('POST https://example.test/status'));
      for (final value in [
        'query-secret',
        'body-secret',
        'header-secret',
        'response-secret',
      ]) {
        expect(logs, isNot(contains(value)));
      }
    },
  );

  test('release logging filters debug and info', () {
    final output = CapturedOutput();
    final logger = AppLogger(release: true, output: output);
    logger.debug('debug-entry');
    logger.info('info-entry');
    logger.warning('warning-entry');
    final logs = output.lines.join('\n');
    expect(logs, contains('warning-entry'));
    expect(logs, isNot(contains('debug-entry')));
    expect(logs, isNot(contains('info-entry')));
  });

  test('disposing the provider container closes its HTTP adapter', () {
    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWithValue(AppConfig.fromValues())],
    );
    final adapter = StubHttpAdapter((_) async => jsonResponse('{}'));
    container.read(dioProvider).httpClientAdapter = adapter;
    container.dispose();
    expect(adapter.closed, isTrue);
  });
}
