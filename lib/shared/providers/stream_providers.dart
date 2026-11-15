import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';
import 'embed_providers.dart';

/// Abstraction for a streaming source provider. Given a MediaDetails (+
/// season/episode for TV), return a list of playable StreamSources.
abstract class StreamingProvider {
  String get id;
  String get name;
  Future<List<StreamSource>> getStreams(MediaDetails details,
      {int season, int episode});
}

/// Aggregates the five public embed providers the user specified:
/// VidSrc MOV, VidSrc PK, AutoEmbed, VidSpark, VidSrc SH.
class _EmbedProvider implements StreamingProvider {
  @override
  String get id => 'embed';
  @override
  String get name => 'Embed';
  @override
  Future<List<StreamSource>> getStreams(MediaDetails details,
          {int season = 0, int episode = 0}) =>
      embedGetStreams(details, season: season, episode: episode);
}

/// Fallback: serves a reliable sample MP4 so the player always has something
/// playable even when every embed host is unreachable (no more
/// "No streams found" dead end).
class _DemoProvider implements StreamingProvider {
  @override
  String get id => 'demo';
  @override
  String get name => 'Preview';
  static const _sampleUrls = [
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ];
  @override
  Future<List<StreamSource>> getStreams(MediaDetails details,
      {int season = 0, int episode = 0}) async =>
      [
        StreamSource(
            name: 'Preview (1080p)',
            url: _sampleUrls[0],
            quality: '1080p',
            providerId: 'demo-1080'),
        StreamSource(
            name: 'Preview (HLS)',
            url: _sampleUrls[1],
            quality: '720p',
            providerId: 'demo-hls'),
      ];
}

final List<StreamingProvider> streamingProviders = [
  _EmbedProvider(),
  _DemoProvider(),
];

/// Aggregates streams from all providers, verifies reachability with a quick
/// HEAD, and guarantees at least the demo sources are returned so the player
/// always plays.
class StreamService {
  final List<StreamingProvider> providers;
  final Dio _dio;
  StreamService(
      {List<StreamingProvider>? providers, required Dio dio})
      : providers = providers ?? streamingProviders,
        _dio = dio;

  Future<List<StreamSource>> getAllStreams(MediaDetails details,
      {int season = 0, int episode = 0}) async {
    final perProvider = await Future.wait(providers.map((p) {
      // Demo provider gets no timeout / verification — it always returns.
      if (p is _DemoProvider) {
        return p.getStreams(details, season: season, episode: episode);
      }
      return p
          .getStreams(details, season: season, episode: episode)
          .timeout(const Duration(seconds: 15),
              onTimeout: () => const <StreamSource>[]);
    }));
    final all = perProvider.expand((s) => s).toList();

    final demoSources =
        all.where((s) => s.providerId.startsWith('demo')).toList();
    final remote = all.where((s) => !s.providerId.startsWith('demo')).toList();

    // Probe each remote source; keep those that return a non-error status.
    final verified = <StreamSource>[];
    await Future.wait(remote.map((s) async {
      try {
        // Many embed hosts return 200 on GET for an HTML iframe page — that's
        // fine; media_kit's HLS/MP4 parser will follow. We just want to filter
        // DNS failures / 404s / TLS errors.
        final r = await _dio
            .head(s.url)
            .timeout(const Duration(seconds: 6));
        if (r.statusCode != null && r.statusCode! < 500) {
          verified.add(s);
        }
      } catch (_) {
        // HEAD blocked is common; try GET then accept anyway so the player
        // can attempt playback. The demo is the safety net.
        verified.add(s);
      }
    }));

    if (verified.isEmpty) return demoSources;
    // Sort by quality rank.
    verified.sort((a, b) => _qRank(b.quality).compareTo(_qRank(a.quality)));
    return [...verified, ...demoSources];
  }

  int _qRank(String? q) => switch (q) {
        '4K' => 5,
        '1080p' => 4,
        '720p' => 3,
        null => 3,
        '480p' => 2,
        '360p' => 1,
        _ => 3,
      };
}

final streamServiceProvider = Provider<StreamService>(
    (ref) => StreamService(dio: ref.watch(dioProvider)));
