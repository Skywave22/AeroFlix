import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';

/// Dio logger that never writes the TMDB API key to the console.
/// Only added in debug builds.
class _RedactingLogInterceptor extends Interceptor {
  String _redact(String url) =>
      url.replaceAll(RegExp(r'api_key=[^&]+'), 'api_key=***');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('[dio] ${options.method} ${_redact(options.uri.toString())}');
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('[dio] error ${err.response?.statusCode} '
          '${_redact(err.requestOptions.uri.toString())}: ${err.type}');
    }
    handler.next(err);
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.tmdbBaseUrl,
    connectTimeout: ApiConstants.connectTimeout,
    receiveTimeout: ApiConstants.receiveTimeout,
    queryParameters: {
      'api_key': ApiConstants.tmdbApiKey,
      'language': ApiConstants.defaultLanguage
    },
    headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
  ));
  if (kDebugMode) {
    dio.interceptors.add(_RedactingLogInterceptor());
  }
  ref.onDispose(dio.close);
  return dio;
});
