import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';

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
  dio.interceptors.add(
      LogInterceptor(requestBody: false, responseBody: false, error: true));
  ref.onDispose(dio.close);
  return dio;
});
