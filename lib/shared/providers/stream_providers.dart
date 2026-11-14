import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final List<StreamingProvider> streamingProviders = [
  _CinezoProvider(),
  _ScreenScapeProvider(),
];

/// Aggregates streams from all enabled providers with a per-provider
/// timeout so one slow provider can't block the rest.
class StreamService {
  final List<StreamingProvider> providers;
  StreamService({List<StreamingProvider>? providers})
      : providers = providers ?? streamingProviders;

  Future<List<StreamSource>> getAllStreams(MediaDetails details,
      {int season = 0, int episode = 0}) async {
    final results = await Future.wait(providers.map((p) => p
        .getStreams(details, season: season, episode: episode)
        .timeout(const Duration(seconds: 20),
            onTimeout: () => const <StreamSource>[])));
    return results.expand((s) => s).toList();
  }
}

final streamServiceProvider = Provider<StreamService>((ref) => StreamService());
