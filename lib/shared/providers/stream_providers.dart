import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';
import 'cinezo_provider.dart';

/// Abstraction for a streaming source provider. Mirrors the Plugins-TJ
/// Nuvio scraper contract: given a MediaDetails (+ season/episode for TV),
/// return a list of playable StreamSources.
abstract class StreamingProvider {
  String get id;
  String get name;
  Future<List<StreamSource>> getStreams(MediaDetails details,
      {int season, int episode});
}

/// Cinezo (cinezo.gd) — VidNest player API with 6 back-end providers
/// (Lamda/Zeta/Alfa/Beta/Prime/Gama). Direct HLS/MP4 URLs returned.
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

/// Placeholder for providers still being ported.
class _PlaceholderProvider implements StreamingProvider {
  final String _id, _name;
  _PlaceholderProvider(this._id, this._name);
  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  Future<List<StreamSource>> getStreams(MediaDetails _,
          {int season = 0, int episode = 0}) async =>
      const [];
}

final List<StreamingProvider> streamingProviders = [
  _CinezoProvider(),
  _PlaceholderProvider('screenscape', 'ScreenScape'),
  // Subsequent phases:
  // _PlaceholderProvider('cinehd', 'CineHD'),
  // _PlaceholderProvider('bingr', 'Bingr'),
  // _PlaceholderProvider('anihype', 'AniHype'),
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
