import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/core/errors/app_exception.dart';
import 'package:novelverse/core/network/api_client.dart';
import 'package:novelverse/core/network/network_exception.dart';

import '../../support/stub_http_adapter.dart';

void main() {
  late Dio dio;
  late ApiClient client;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1/'));
    client = ApiClient(dio);
  });
  tearDown(() => dio.close(force: true));

  test('decodes JSON and preserves method, query and request body', () async {
    final adapter = StubHttpAdapter((options) async {
      expect(options.method, 'PATCH');
      expect(options.uri.path, '/v1/settings');
      expect(options.queryParameters['revision'], 2);
      expect(options.data, {'enabled': true});
      expect(options.headers['X-Request-Id'], 'test');
      return jsonResponse('{"saved":true}');
    });
    dio.httpClientAdapter = adapter;

    final result = await client.request<bool>(
      'settings',
      method: 'PATCH',
      queryParameters: {'revision': 2},
      data: {'enabled': true},
      options: Options(headers: {'X-Request-Id': 'test'}),
      decode: (data) => (data as Map<String, dynamic>)['saved'] as bool,
    );
    expect(result, isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test(
    'preserves HTTP failure category and original cause without retry',
    () async {
      final adapter = StubHttpAdapter(
        (_) async => jsonResponse('{"message":"unavailable"}', statusCode: 503),
      );
      dio.httpClientAdapter = adapter;
      await expectLater(
        client.get('status', decode: (data) => data),
        throwsA(
          isA<NetworkException>()
              .having((e) => e.kind, 'kind', NetworkFailureKind.http)
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.cause, 'cause', isA<DioException>()),
        ),
      );
      expect(adapter.requests, hasLength(1));
    },
  );

  test('maps receive timeout', () async {
    dio.httpClientAdapter = StubHttpAdapter((options) async {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    });
    await expectLater(
      client.get('slow', decode: (data) => data),
      throwsA(
        isA<NetworkException>().having(
          (e) => e.kind,
          'kind',
          NetworkFailureKind.timeout,
        ),
      ),
    );
  });

  test('cancels an in-flight request', () async {
    final started = Completer<void>();
    final response = Completer<ResponseBody>();
    dio.httpClientAdapter = StubHttpAdapter((_) {
      started.complete();
      return response.future;
    });
    final token = CancelToken();
    final request = client.get(
      'slow',
      decode: (data) => data,
      cancelToken: token,
    );
    final expectation = expectLater(
      request,
      throwsA(
        isA<NetworkException>().having(
          (e) => e.kind,
          'kind',
          NetworkFailureKind.cancelled,
        ),
      ),
    );
    await started.future;
    token.cancel();
    response.complete(jsonResponse('{}'));
    await expectation;
  });

  test('turns decoder failures into typed data errors', () async {
    dio.httpClientAdapter = StubHttpAdapter((_) async => jsonResponse('[]'));
    await expectLater(
      client.get('invalid', decode: (data) => data as Map<String, dynamic>),
      throwsA(isA<DataFormatException>()),
    );
  });

  test('turns malformed response JSON into typed data errors', () async {
    dio.httpClientAdapter = StubHttpAdapter((_) async => jsonResponse('{'));
    await expectLater(
      client.get('invalid-json', decode: (data) => data),
      throwsA(isA<DataFormatException>()),
    );
  });

  test('does not swallow business exceptions thrown by a decoder', () async {
    dio.httpClientAdapter = StubHttpAdapter((_) async => jsonResponse('{}'));
    const error = DataFormatException('Expected field missing.');
    await expectLater(
      client.get<Object>('invalid', decode: (_) => throw error),
      throwsA(same(error)),
    );
  });

  test('fails before sending when a relative URL has no base URL', () async {
    dio.options.baseUrl = '';
    final adapter = StubHttpAdapter((_) async => jsonResponse('{}'));
    dio.httpClientAdapter = adapter;
    await expectLater(
      client.get('/status', decode: (data) => data),
      throwsA(isA<ConfigurationException>()),
    );
    expect(adapter.requests, isEmpty);
  });

  test('allows an explicit URL without an API base URL', () async {
    dio.options.baseUrl = '';
    dio.httpClientAdapter = StubHttpAdapter((_) async => jsonResponse('{}'));
    expect(
      await client.get(
        'https://files.example.test/info',
        decode: (data) => data,
      ),
      isEmpty,
    );
  });
}
