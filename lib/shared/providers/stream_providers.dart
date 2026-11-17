import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

import '../../core/providers/tj_providers_service.dart';
import '../models/media_details.dart';
import '../models/stream_source.dart';

/// Resolves playable links for a title through the TJ-Plugins providers
/// (Cinezo, ScreenScape, Nxsha, AniHype, KatDrama by default).
///
/// Everything here is real: the provider bundles are downloaded from GitHub,
/// executed in QuickJS, and return direct HLS/MP4 links with the headers each
/// server expects. Nothing is simulated and there is no demo content.
class StreamService {
  StreamService(this._providers);

  final ProviderService _providers;

  /// Fetch links for [media] (optionally for a specific episode).
  ///
  /// Returns an empty list when no provider has a working link — callers should
  /// offer the trailer as a fallback rather than pretending to play something.
  Future<List<StreamSource>> getAllStreams(
    MediaDetails media, {
    int season = 0,
    int episode = 0,
    List<String>? onlyProviderIds,
  }) async {
    final isTv = media.type == MediaType.tv;
    final results = await _providers.getStreams(
      tmdbId: '${media.id}',
      mediaType: isTv ? 'tv' : 'movie',
      season: isTv && season > 0 ? season : null,
      episode: isTv && episode > 0 ? episode : null,
      onlyProviderIds: onlyProviderIds,
    );

    final sources = results
        .map((s) => StreamSource(
              url: s.url,
              name: s.name,
              providerId: s.provider,
              quality: s.quality,
              language: s.language,
              size: s.size,
              headers: s.headers,
              subtitles: [
                for (final sub in s.subtitles)
                  SubtitleTrack(
                    url: sub.url,
                    language: sub.language,
                    label: sub.language,
                  ),
              ],
            ))
        .where((s) => s.url.isNotEmpty)
        .toList();

    sources.sort((a, b) {
      final hq = _rank(b.quality).compareTo(_rank(a.quality));
      if (hq != 0) return hq;
      return _hindiFirst(a).compareTo(_hindiFirst(b));
    });
    return sources;
  }

  static int _rank(String? q) {
    final s = (q ?? '').toLowerCase();
    if (s.contains('4k') || s.contains('2160')) return 5;
    if (s.contains('1440')) return 4;
    if (s.contains('1080')) return 3;
    if (s.contains('720')) return 2;
    if (s.contains('480')) return 1;
    return 0;
  }

  static int _hindiFirst(StreamSource s) {
    final text = '${s.language ?? ''} ${s.name}'.toLowerCase();
    return text.contains('hindi') ? 0 : 1;
  }
}

final streamServiceProvider = Provider<StreamService>((ref) {
  return StreamService(ref.watch(providerServiceProvider));
});

/// Convenience provider for widgets that just want the counts/list.
final streamSourcesProvider =
    FutureProvider.family<List<StreamSource>, MediaDetails>((ref, media) {
  return ref.watch(streamServiceProvider).getAllStreams(media);
});
