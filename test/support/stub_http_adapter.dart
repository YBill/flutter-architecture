import 'dart:typed_data';

import 'package:dio/dio.dart';

final class StubHttpAdapter implements HttpClientAdapter {
  StubHttpAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) => closed = true;
}

ResponseBody jsonResponse(String json, {int statusCode = 200}) =>
    ResponseBody.fromString(
      json,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
