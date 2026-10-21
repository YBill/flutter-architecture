import 'package:dio/dio.dart';

import '../errors/app_exception.dart';

enum NetworkFailureKind { timeout, connection, cancelled, http, unknown }

final class NetworkException extends AppException {
  const NetworkException({
    required this.kind,
    required String message,
    this.statusCode,
    Object? cause,
  }) : super(message, cause: cause);

  factory NetworkException.fromDio(DioException error) {
    final kind = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => NetworkFailureKind.timeout,
      DioExceptionType.connectionError ||
      DioExceptionType.badCertificate => NetworkFailureKind.connection,
      DioExceptionType.cancel => NetworkFailureKind.cancelled,
      DioExceptionType.badResponse => NetworkFailureKind.http,
      DioExceptionType.unknown => NetworkFailureKind.unknown,
    };
    return NetworkException(
      kind: kind,
      message: 'HTTP request failed (${kind.name}).',
      statusCode: error.response?.statusCode,
      cause: error,
    );
  }

  final NetworkFailureKind kind;
  final int? statusCode;
}
