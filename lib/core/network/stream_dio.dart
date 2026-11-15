import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A separate Dio instance for scraping third-party embed hosts (no TMDB
/// base URL, no api_key injection, browser-like headers).
final streamDioProvider = Provider<Dio>((ref) {
  final d = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
    },
    followRedirects: true,
    validateStatus: (s) => s != null && s < 500,
  ));
  ref.onDispose(d.close);
  return d;
});
