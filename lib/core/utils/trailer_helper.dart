import 'package:url_launcher/url_launcher.dart';
import '../../shared/models/media_details.dart';

/// Returns the best available YouTube trailer URL for this title, or null.
String? trailerUrl(MediaDetails d) {
  // Pick the first YouTube Trailer entry (prefer "Official Trailer" if we can).
  VideoTrailer? best;
  for (final v in d.trailers) {
    if (v.site.toLowerCase() != 'youtube') continue;
    if (v.type.toLowerCase() != 'trailer') continue;
    best ??= v;
    if (v.name.toLowerCase().contains('official')) {
      best = v;
      break;
    }
  }
  return best?.youtubeUrl;
}

/// A trailer is only a *fallback*: real playback always comes from the
/// TJ-Plugins providers (see StreamService).
bool hasTrailer(MediaDetails d) => trailerUrl(d) != null;

/// Opens the trailer (if available) or TMDB page as a fallback.
/// Opens the trailer (if available) or the TMDB page as a fallback.
///
/// Deliberately does *not* call `canLaunchUrl` first: on Android 11+ an
/// unresolved intent returns false unless the target scheme is declared in
/// `<queries>` (see AndroidManifest), which used to make this report "no app
/// found" even when YouTube was installed. `launchUrl` already returns false
/// for a genuinely unopenable URL, and that failure is surfaced to the user.
Future<bool> openTrailer(MediaDetails d) async {
  final url = trailerUrl(d);
  final candidates = <String>[
    if (url != null) url,
    'https://www.themoviedb.org/${d.type.name}/${d.id}',
  ];
  for (final target in candidates) {
    try {
      final uri = Uri.parse(target);
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Try the next candidate.
    }
  }
  return false;
}
