import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/core_providers.dart';
import 'api_client.dart';
import 'network_log_interceptor.dart';

part 'network_providers.g.dart';

@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final config = ref.watch(appConfigProvider);
  final client = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUri?.toString() ?? '',
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ),
  );
  if (config.enableHttpLogging && !kReleaseMode) {
    client.interceptors.add(
      NetworkLogInterceptor(ref.watch(appLoggerProvider)),
    );
  }
  ref.onDispose(() => client.close(force: true));
  return client;
}

@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) => ApiClient(ref.watch(dioProvider));
