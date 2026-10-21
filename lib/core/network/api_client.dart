import 'package:dio/dio.dart';

import '../errors/app_exception.dart';
import 'network_exception.dart';

typedef ResponseDecoder<T> = T Function(Object? data);

/// Transport and decoding only. Business envelopes belong in API/repositories.
final class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<T> get<T>(
    String path, {
    required ResponseDecoder<T> decode,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => request(
    path,
    decode: decode,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  Future<T> post<T>(
    String path, {
    required ResponseDecoder<T> decode,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) => request(
    path,
    method: 'POST',
    decode: decode,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
  );

  /// Also supports PUT/PATCH/DELETE, FormData, bytes and streamed responses.
  Future<T> request<T>(
    String path, {
    String method = 'GET',
    required ResponseDecoder<T> decode,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    _checkConfiguration(path);
    final Response<Object?> response;
    try {
      response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: (options ?? Options()).copyWith(method: method),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
    } on DioException catch (error, stackTrace) {
      if (error.error is FormatException) {
        Error.throwWithStackTrace(
          DataFormatException('Unable to decode the response.', cause: error),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(NetworkException.fromDio(error), stackTrace);
    }

    try {
      return decode(response.data);
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DataFormatException('Unable to decode the response.', cause: error),
        stackTrace,
      );
    }
  }

  Future<void> download(
    String url,
    String savePath, {
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    _checkConfiguration(url);
    try {
      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
    } on DioException catch (error, stackTrace) {
      Error.throwWithStackTrace(NetworkException.fromDio(error), stackTrace);
    }
  }

  void _checkConfiguration(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null &&
        uri.hasAuthority &&
        {'http', 'https'}.contains(uri.scheme)) {
      return;
    }
    if (_dio.options.baseUrl.isEmpty) {
      throw const ConfigurationException(
        'API_BASE_URL has not been configured.',
      );
    }
  }
}
