import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/stream_dio.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';
import 'embed_providers.dart';

/// Aggregates streams from the five public embed providers the user
/// specified (VidSrc MOV, VidSrc PK, AutoEmbed, VidSpark, VidSrc SH). Each
/// resolver returns direct m3u8 URLs ready for media_kit to play.
class StreamService {
  final Dio dio;
  StreamService({required this.dio});

  Future<List<StreamSource>> getAllStreams(MediaDetails details,
      {int season = 0, int episode = 0}) async {
    // Embed resolvers hit arbitrary hosts; give each its own browser-Dio.
    final list = await embedGetStreams(dio, details,
        season: season, episode: episode);
    // De-dup by URL.
    final seen = <String>{};
    final unique = <StreamSource>[];
    for (final s in list) {
      if (s.url.isEmpty) continue;
      final key = s.url.split('?').first;
      if (seen.add(key)) unique.add(s);
    }
    // Sort by quality rank (highest first).
    unique.sort((a, b) => _rank(b.quality).compareTo(_rank(a.quality)));
    return unique;
  }

  int _rank(String? q) => switch (q) {
        '4K' => 5,
        '1080p' => 4,
        '720p' => 3,
        '480p' => 2,
        _ => 0,
      };
}

final streamServiceProvider =
    Provider<StreamService>((ref) => StreamService(dio: ref.watch(streamDioProvider)));
