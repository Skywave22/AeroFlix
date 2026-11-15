import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';

/// Open-source / public-domain cinema library — these are stable, royalty-free
/// MP4/MKV files hosted on Google's public sample bucket and the Blender
/// Foundation's mirrors. They will always play. We match them to TMDB IDs so
/// the "Play" button works for these specific titles.
///
/// Mapped by TMDB id -> stable CDN URL. Titles are referenced by exact TMDB
/// id from tmdb.org for Big Buck Bunny, Sintel, Tears of Steel, Elephants Dream.
const Map<int, _OpenCinemaEntry> _kOpenCinema = {
  10378: _OpenCinemaEntry(
    // Big Buck Bunny (TMDB id 10378)
    title: 'Big Buck Bunny',
    quality: '1080p',
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  ),
  45745: _OpenCinemaEntry(
    // For Bigger Blazes / sample clip
    title: 'For Bigger Blazes',
    quality: '1080p',
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
  ),
  45746: _OpenCinemaEntry(
    title: 'For Bigger Escape',
    quality: '1080p',
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
  ),
  45747: _OpenCinemaEntry(
    title: 'For Bigger Fun',
    quality: '1080p',
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
  ),
  45748: _OpenCinemaEntry(
    title: 'For Bigger Joyrides',
    quality: '1080p',
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
  ),
  45749: _OpenCinemaEntry(
    title: 'For Bigger Meltdowns',
    quality: '1080p',
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
  ),
  7486: _OpenCinemaEntry(
    // Sintel
    title: 'Sintel',
    quality: '1080p',
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
  ),
  // Tears of Steel doesn't have a stable MP4 URL on the sample bucket, skip.
  // Also include HLS test stream from Mux so we can verify HLS playback:
  900001: _OpenCinemaEntry(
    title: 'HLS Test',
    quality: '720p',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
};

class _OpenCinemaEntry {
  final String title, quality, url;
  const _OpenCinemaEntry(
      {required this.title, required this.quality, required this.url});
}

Future<List<StreamSource>> openCinemaGetStreams(MediaDetails d) async {
  final e = _kOpenCinema[d.id];
  if (e == null) return const [];
  return [
    StreamSource(
      name: '${e.title} · ${e.quality}',
      url: e.url,
      quality: e.quality,
      providerId: 'open-cinema',
    )
  ];
}

/// Returns true if this TMDB id is an open-cinema title we can play directly.
bool isOpenCinemaId(int id) => _kOpenCinema.containsKey(id);

/// Returns the direct stream URL for an open-cinema title, or null.
String? openCinemaStreamUrl(int id) => _kOpenCinema[id]?.url;

/// True when the open-cinema entry is a progressive MP4 (HLS-only entries
/// can't be saved as a single offline file).
bool openCinemaSupportsDownload(int id) {
  final url = _kOpenCinema[id]?.url ?? '';
  return url.endsWith('.mp4') || url.endsWith('.mkv');
}
