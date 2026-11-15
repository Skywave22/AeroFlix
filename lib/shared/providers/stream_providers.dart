import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/media_details.dart';
import '../models/stream_source.dart';
import 'open_cinema_provider.dart';

/// Service wrapper consumed by the player — kept stable so the player
/// controller doesn't need to know about source policy.
class StreamService {
  Future<List<StreamSource>> getAllStreams(MediaDetails media,
      {int season = 0, int episode = 0}) async {
    // Open-cinema only for now. TV episodes have no direct sources.
    if (media.type == MediaType.tv) return const [];
    return openCinemaGetStreams(media);
  }
}

final streamServiceProvider = Provider((ref) => StreamService());

/// ────────────────────────────────────────────────────────────────────────────
/// Stream sources — V2
///
/// V1 attempted to scrape piracy embeds (VidSrc / VidSpark / AutoEmbed) but
/// those hosts run heavy in-browser JS/WASM anti-bot with hourly rotating
/// domains and cannot be resolved from a pure-Dart HTTP client. The fix is
/// three-pronged:
///   1. Directly play a small library of open-source / public-domain shorts
///      (Big Buck Bunny, Sintel, etc.) served from stable CDN URLs.
///   2. For other titles, the "Play" button opens the official YouTube trailer
///      in an external app / browser (see trailer_helper.dart).
///   3. The details screen will soon show a TMDB "Watch Providers" panel so
///      users can see where a title is legitimately streaming.
/// ────────────────────────────────────────────────────────────────────────────

/// Returns playable direct-stream URLs for a title, sorted best quality first.
/// Never returns an empty list for open-cinema titles; returns empty list
/// for everything else so the UI can fall back to trailer / providers.
final streamSourcesProvider =
    FutureProvider.family<List<StreamSource>, MediaDetails>((ref, media) async {
  final sources = <StreamSource>[];

  // 1) Open-source cinema — always reliable.
  sources.addAll(await openCinemaGetStreams(media));

  // Sort best quality first.
  int rank(String? q) {
    final s = (q ?? '').toLowerCase();
    return switch (s) {
      '4k' || '2160p' => 5,
      '1080p' => 4,
      '720p' || '' => 3,
      '480p' => 2,
      _ => 1,
    };
  }

  sources.sort((a, b) =>
      rank(b.quality).compareTo(rank(a.quality)));
  return sources;
});
