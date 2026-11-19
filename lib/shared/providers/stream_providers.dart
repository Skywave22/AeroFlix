import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

import '../../core/providers/tj_providers_service.dart';
import '../models/media_details.dart';
import '../models/stream_source.dart';

class _CachedResolution {
  const _CachedResolution(this.sources, this.at);
  final List<StreamSource> sources;
  final DateTime at;
}

/// Result of one provider for one title.
class ProviderResolution {
  const ProviderResolution({
    required this.providerId,
    this.sources = const [],
    this.error,
    this.elapsed = Duration.zero,
  });

  final String providerId;
  final List<StreamSource> sources;
  final String? error;
  final Duration elapsed;

  bool get ok => error == null;
}

/// Resolves playable links for a title through the TJ-Plugins **All-in-one**
/// provider (`tjaio`), which queries every working TJ site at once and merges
/// the results — one bundle covers movies, series, anime and K-dramas.
///
/// Everything here is real: provider bundles ship with the app and auto-update
/// from GitHub, they run in QuickJS, and they return direct HLS/MP4 links with
/// the headers each server expects. Nothing is simulated.
class StreamService {
  StreamService(this._providers);

  final ProviderService _providers;

  /// Recently resolved links, so going back into a title (or bouncing between
  /// episodes) never pays the ~40 s provider round-trip twice.
  static final Map<String, _CachedResolution> _cache = {};
  static const Duration _cacheTtl = Duration(minutes: 20);

  static String _key(String id, String type, int season, int episode) =>
      '$id|$type|$season|$episode';

  /// Cached links for a title, or null when there is nothing fresh.
  List<StreamSource>? cachedStreams(MediaDetails media,
      {int season = 0, int episode = 0}) {
    final key = _key('${media.id}', media.type == MediaType.tv ? 'tv' : 'movie',
        season, episode);
    final hit = _cache[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return hit.sources;
  }

  void _remember(String id, String type, int season, int episode,
      List<StreamSource> sources) {
    if (sources.isEmpty) return;
    _cache[_key(id, type, season, episode)] =
        _CachedResolution(sources, DateTime.now());
    if (_cache.length > 40) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Which providers will be queried, in order.
  List<String> get providers => _providers.enabledIds;

  /// Query providers one by one, emitting each result as soon as it lands so
  /// the player can start on the first hit instead of waiting for the slowest
  /// provider.
  Stream<ProviderResolution> resolveStreams(
    MediaDetails media, {
    int season = 0,
    int episode = 0,
    List<String>? onlyProviderIds,
  }) async* {
    final isTv = media.type == MediaType.tv;
    final cached = cachedStreams(media, season: season, episode: episode);
    if (cached != null) {
      yield ProviderResolution(
        providerId: 'cache',
        sources: cached,
        elapsed: Duration.zero,
      );
      return;
    }
    await for (final outcome in _providers.streamStreams(
      tmdbId: '${media.id}',
      mediaType: isTv ? 'tv' : 'movie',
      season: isTv && season > 0 ? season : null,
      episode: isTv && episode > 0 ? episode : null,
      onlyProviderIds: onlyProviderIds,
    )) {
      final mapped = _map(outcome.streams);
      if (mapped.isNotEmpty) {
        _remember(
            '${media.id}',
            isTv ? 'tv' : 'movie',
            isTv && season > 0 ? season : 0,
            isTv && episode > 0 ? episode : 0,
            mapped);
      }
      yield ProviderResolution(
        providerId: outcome.providerId,
        sources: mapped,
        error: outcome.error,
        elapsed: outcome.elapsed,
      );
    }
  }

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
    final cached = cachedStreams(media, season: season, episode: episode);
    if (cached != null) return cached;
    final results = await _providers.getStreams(
      tmdbId: '${media.id}',
      mediaType: isTv ? 'tv' : 'movie',
      season: isTv && season > 0 ? season : null,
      episode: isTv && episode > 0 ? episode : null,
      onlyProviderIds: onlyProviderIds,
    );
    final mapped = _map(results);
    _remember(
        '${media.id}',
        isTv ? 'tv' : 'movie',
        isTv && season > 0 ? season : 0,
        isTv && episode > 0 ? episode : 0,
        mapped);
    return mapped;
  }

  List<StreamSource> _map(List<StreamResult> results) {
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

    sources.sort(compareSources);
    return sources;
  }

  /// Playability-first ordering.
  ///
  /// A 4K link that never opens is worthless, so links advertised as
  /// "(may not play)" or served through a packer redirect are pushed to the
  /// end, adaptive HLS wins over raw files, and quality/language only break
  /// ties. The player also auto-advances down this list when a source fails.
  static int compareSources(StreamSource a, StreamSource b) =>
      score(b).compareTo(score(a));

  static int score(StreamSource s) {
    final url = s.url.toLowerCase();
    final name = s.name.toLowerCase();
    var score = 0;
    if (name.contains('may not play')) score -= 100;
    if (url.contains('pitro') || url.contains('/stream/')) score -= 12;
    if (url.contains('.m3u8')) {
      score += 30;
    } else if (url.contains('.mp4')) {
      score += 24;
    } else if (url.contains('.mkv')) {
      score += 18;
    }
    score += _rank(s.quality);
    if (_hindiFirst(s) == 0) score += 3;
    return score;
  }

  /// Quality ranking tuned for phones on mobile data: 1080p streams start and
  /// stay smooth, 4K from these one-off CDNs is what makes playback stall, so
  /// it ranks below 1080p/720p instead of above it.
  static int _rank(String? q) {
    final s = (q ?? '').toLowerCase();
    if (s.contains('1080') || s.contains('fhd')) return 5;
    if (s.contains('720') || s.contains('hd')) return 4;
    if (s.contains('4k') || s.contains('2160')) return 3;
    if (s.contains('1440')) return 2;
    if (s.contains('480') || s.contains('sd')) return 1;
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
