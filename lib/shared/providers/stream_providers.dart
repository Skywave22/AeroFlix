import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';

/// Abstraction for a streaming source provider. Mirrors the Plugins-TJ
/// Nuvio scraper contract: given a TMDB id + media type + season/episode,
/// return a list of playable StreamSources.
///
/// Providers are implemented as Dart ports of the JS plugins in
/// TJ-Plugins / Plugins-TJ. They run via HTTP (dio), not by embedding
/// the JS. Each provider handles its own site's URL patterns and
/// stream extraction.
abstract class StreamingProvider {
  /// Provider id (matches manifest id from Plugins-TJ).
  String get id;

  /// Human-readable provider name.
  String get name;

  /// Fetch playable stream sources for the given TMDB title.
  /// Movies: season=0, episode=0.
  /// TV: season>=1, episode>=1.
  Future<List<StreamSource>> getStreams({
    required int tmdbId,
    required MediaType mediaType,
    int season = 0,
    int episode = 0,
  });
}

/// Placeholder provider that will be replaced with real implementations.
/// Returns empty list so the UI shows a graceful "no sources" state.
class _PlaceholderProvider implements StreamingProvider {
  final String _id, _name;
  _PlaceholderProvider(this._id, this._name);
  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  Future<List<StreamSource>> getStreams(
          {required int tmdbId,
          required MediaType mediaType,
          int season = 0,
          int episode = 0}) async =>
      const [];
}

/// Registry of available streaming providers.
/// Phase 1 will implement Cinezo + ScreenScape first (4K + 30+ servers).
final List<StreamingProvider> streamingProviders = [
  _PlaceholderProvider('cinezo', 'Cinezo (4K)'),
  _PlaceholderProvider('screenscape', 'ScreenScape'),
  // Added in subsequent phases:
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

  Future<List<StreamSource>> getAllStreams({
    required int tmdbId,
    required MediaType mediaType,
    int season = 0,
    int episode = 0,
  }) async {
    final results = await Future.wait(providers.map((p) => p
        .getStreams(
            tmdbId: tmdbId,
            mediaType: mediaType,
            season: season,
            episode: episode)
        .timeout(const Duration(seconds: 15),
            onTimeout: () => const <StreamSource>[])));
    return results.expand((s) => s).toList();
  }
}

final streamServiceProvider = Provider<StreamService>((ref) => StreamService());
