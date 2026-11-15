import 'package:url_launcher/url_launcher.dart';
import '../../shared/models/media_details.dart';
import '../providers/open_cinema_provider.dart' show isOpenCinemaId;

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

/// True if we can play this title directly in-app (open-cinema / downloaded).
bool canPlayDirectly(MediaDetails d) => isOpenCinemaId(d.id);

/// Opens the trailer (if available) or TMDB page as a fallback.
Future<bool> openTrailer(MediaDetails d) async {
  final url = trailerUrl(d);
  final target = url ?? 'https://www.themoviedb.org/${d.type.name}/${d.id}';
  final uri = Uri.parse(target);
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}
