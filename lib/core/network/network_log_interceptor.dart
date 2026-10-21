import 'package:dio/dio.dart';

import '../logging/app_logger.dart';

/// Logs metadata only: headers, bodies and query values never enter the log.
final class NetworkLogInterceptor extends Interceptor {
  NetworkLogInterceptor(this._logger);

  final AppLogger _logger;
  final Expando<Stopwatch> _timings = Expando<Stopwatch>();

  String _requestLabel(RequestOptions options) =>
      '${options.method} ${options.uri.origin}${options.uri.path}';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _timings[options] = Stopwatch()..start();
    _logger.debug('HTTP → ${_requestLabel(options)}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final elapsed = _timings[response.requestOptions]?.elapsedMilliseconds;
    _logger.debug(
      'HTTP ← ${_requestLabel(response.requestOptions)} '
      '${response.statusCode} (${elapsed ?? 0} ms)',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.debug(
      'HTTP ← ${_requestLabel(err.requestOptions)} '
      '${err.response?.statusCode ?? err.type.name}',
    );
    handler.next(err);
  }
}
