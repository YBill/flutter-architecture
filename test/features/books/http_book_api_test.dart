import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/core/errors/app_exception.dart';
import 'package:novelverse/core/network/api_client.dart';
import 'package:novelverse/core/network/network_exception.dart';
import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/books/data/http_book_api.dart';

import '../../support/stub_http_adapter.dart';
import '../reader/helpers/mock_book_api.dart';

void main() {
  late Dio dio;
  late HttpBookApi api;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8787/api/v1/'));
    api = HttpBookApi(ApiClient(dio));
  });
  tearDown(() => dio.close(force: true));

  test(
    'all book requests preserve the API prefix and decode server responses',
    () async {
      final fixture = MockBookApi();
      final detail = await fixture.fetchDetail(sampleBookId);
      final catalog = await fixture.fetchCatalog(sampleBookId);
      final target = await fixture.fetchChapter(
        sampleBookId,
        catalog.chapters[149],
      );
      final detailJson = jsonDecode(
        File('server/data/books/claimed_ruthless_alpha/detail.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      detailJson['firstChapter'] = detail.firstChapter!.toJson();
      final responses = <String, String>{
        '/api/v1/books': File('server/data/books/books.json')
            .readAsStringSync(),
        '/api/v1/books/$sampleBookId': jsonEncode(detailJson),
        '/api/v1/books/$sampleBookId/chapters': jsonEncode(catalog.toJson()),
        '/api/v1/books/$sampleBookId/recommendations': File(
          'server/data/books/recommendations.json',
        ).readAsStringSync(),
        '/api/v1/books/$sampleBookId/chapters/${target.id}': jsonEncode(
          target.toJson(),
        ),
      };
      final adapter = StubHttpAdapter((options) async {
        expect(options.method, 'GET');
        return jsonResponse(responses[options.uri.path]!);
      });
      dio.httpClientAdapter = adapter;
      expect((await api.fetchBooks()).first.id, sampleBookId);
      expect(
        (await api.fetchDetail(sampleBookId)).firstChapter!.body,
        detail.firstChapter!.body,
      );
      expect((await api.fetchCatalog(sampleBookId)).chapters, hasLength(203));
      expect(await api.fetchRecommendations(sampleBookId), hasLength(6));
      expect(
        (await api.fetchChapter(sampleBookId, catalog.chapters[149])).body,
        target.body,
      );
      expect(adapter.requests, hasLength(5));
      expect(
        adapter.requests.last.uri.path,
        '/api/v1/books/$sampleBookId/chapters/${target.id}',
      );
    },
  );

  test(
    'server failure propagates instead of falling back to bundled books',
    () async {
      final adapter = StubHttpAdapter(
        (_) async => jsonResponse(
          '{"error":{"code":"book_not_found"}}',
          statusCode: 404,
        ),
      );
      dio.httpClientAdapter = adapter;
      await expectLater(
        api.fetchDetail(sampleBookId),
        throwsA(
          isA<NetworkException>().having(
            (error) => error.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    },
  );

  test('invalid response models produce typed data errors', () async {
    dio.httpClientAdapter = StubHttpAdapter(
      (_) async => jsonResponse('{"items":[{"id":"broken"}]}'),
    );
    await expectLater(api.fetchBooks(), throwsA(isA<DataFormatException>()));
  });
}
