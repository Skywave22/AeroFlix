import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';
import 'cinezo_provider.dart';
import 'screenscape_provider.dart';

/// Abstraction for a streaming source provider. Mirrors the Plugins-TJ
/// Nuvio scraper contract: given a MediaDetails (+ season/episode for TV),
/// return a list of playable StreamSources.
abstract class StreamingProvider {
  String get id;
  String get name;
  Future<List<StreamSource>> getStreams(MediaDetails details,
      {int season, int episode});
}

/// Cinezo (cinezo.gd) — VidNest player API with 6 back-end providers.
class _CinezoProvider implements StreamingProvider {
  @override
  String get id => 'cinezo';
  @override
  String get name => 'Cinezo (4K)';
  @override
  Future<List<StreamSource>> getStreams(MediaDetails details,
          {int season = 0, int episode = 0}) =>
      cinezoGetStreams(details, season: season, episode: episode);
}

/// ScreenScape (nxsha.app) — AES-encrypted JSON API returning multi-server
/// m3u8/mp4 sources.
class _ScreenScapeProvider implements StreamingProvider {
  @override
  String get id => 'screenscape';
  @override
  String get name => 'ScreenScape';
  @override
  Future<List<StreamSource>> getStreams(MediaDetails details,
          {int season = 0, int episode = 0}) =>
      nxshaGetStreams(details, season: season, episode: episode);
}

/// Fallback: serves a reliable sample MP4 so the player always has something
/// playable (prevents "No streams found" when scrapers are blocked/offline).
class _DemoProvider implements StreamingProvider {
  @override
  String get id => 'demo';
  @override
  String get name => 'Preview';
  static const _sampleUrls = [
    // Big Buck Bunny — reliable public MP4 test asset hosted on a CDN.
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ];
  @override
  Future<List<StreamSource>> getStreams(MediaDetails details,
      {int season = 0, int episode = 0}) async {
    return [
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
}

final List<StreamingProvider> streamingProviders = [
  _CinezoProvider(),
  _ScreenScapeProvider(),
  _DemoProvider(),
];

/// Aggregates streams from all enabled providers with a per-provider
/// timeout so one slow provider can't block the rest. The DemoProvider
/// guarantees the player always has at least one source.
class StreamService {
  final List<StreamingProvider> providers;
  final Dio _dio;
  StreamService(
      {List<StreamingProvider>? providers, required Dio dio})
      : providers = providers ?? streamingProviders,
        _dio = dio;

  Future<List<StreamSource>> getAllStreams(MediaDetails details,
      {int season = 0, int episode = 0}) async {
    final results = await Future.wait(providers.map((p) => p
        .getStreams(details, season: season, episode: episode)
        .timeout(const Duration(seconds: 20),
            onTimeout: () => const <StreamSource>[])));
    final all = results.expand((s) => s).toList();
    // Verify remote sources are reachable; drop unreachable ones. Demo is kept.
    final verified = <StreamSource>[];
    for (final s in all) {
      if (s.providerId.startsWith('demo')) {
        verified.add(s);
        continue;
      }
      try {
        final r = await _dio.head(s.url).timeout(const Duration(seconds: 6));
        if (r.statusCode != null && r.statusCode! < 400) {
          verified.add(s);
        }
      } catch (_) {
        // source unreachable; skip
      }
    }
    // If nothing verified, fall back to the demo sources explicitly.
    if (verified.isEmpty) {
      return _DemoProvider()
          .getStreams(details, season: season, episode: episode);
    }
    return verified;
  }
}

final streamServiceProvider = Provider<StreamService>(
    (ref) => StreamService(dio: ref.watch(dioProvider)));
