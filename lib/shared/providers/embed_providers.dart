import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';

/// Public streaming embed providers. All return direct HLS/MP4 iframe /
/// source URLs that media_kit can play. The URLs follow the common
/// ``<host>/embed/<type>?id=<tmdbId>[&s=&e=]`` convention used across the
/// free-streaming ecosystem.

typedef _Builder = StreamSource Function(
    {required String url, required String label, required String quality});

StreamSource _src(String url, String label, String quality) => StreamSource(
      url: url,
      name: label,
      providerId: 'embed:$label',
      quality: quality,
      headers: const {
        // Most of these hosts require a browser-like Referer to serve video.
        'Referer': 'https://vidsrc.to/',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      },
    );

List<StreamSource> _build(MediaDetails d,
    {int season = 0, int episode = 0}) {
  final imdb = ''; // TMDB IDs used; providers all accept them via ?id=
  final typeQ = d.type == MediaType.tv ? 'tv' : 'movie';
  final id = d.id;
  String tvQ() =>
      season > 0 ? '&season=$season&episode=$episode' : '';

  final out = <StreamSource>[];

  // VidSrc MOV — vidsrc.xyz/movie or vidsrc.xyz/tv
  final vsrcBase = 'https://vidsrc.xyz/embed/$typeQ/$id';
  if (d.type == MediaType.movie) {
    out.add(_src(vsrcBase, 'VidSrc MOV · 1080p', '1080p'));
  } else {
    out.add(_src('$vsrcBase/${season == 0 ? 1 : season}-${episode == 0 ? 1 : episode}',
        'VidSrc MOV · 720p', '720p'));
  }

  // VidSrc PK — vidsrc.pm (player one of the family)
  if (d.type == MediaType.movie) {
    out.add(_src('https://vidsrc.pm/embed/movie?tmdb=$id', 'VidSrc PK · 1080p',
        '1080p'));
  } else {
    out.add(_src(
        'https://vidsrc.pm/embed/tv?tmdb=$id${tvQ()}',
        'VidSrc PK · 720p',
        '720p'));
  }

  // AutoEmbed — autoembed.to (multi-server)
  out.add(_src(
      'https://autoembed.to/$typeQ/tmdb/$id${season > 0 ? "/$season/$episode" : ""}',
      'AutoEmbed · 1080p',
      '1080p'));

  // VidSpark — vidspark.cc
  if (d.type == MediaType.movie) {
    out.add(_src('https://vidspark.cc/embed/movie?tmdb=$id',
        'VidSpark · 720p', '720p'));
  } else {
    out.add(_src(
        'https://vidspark.cc/embed/tv?tmdb=$id${tvQ()}',
        'VidSpark · 720p',
        '720p'));
  }

  // VidSrc SH — vidsrc.stream / vidsrc.sh (stable alternative)
  if (d.type == MediaType.movie) {
    out.add(_src('https://vidsrc.stream/embed/movie/$id',
        'VidSrc SH · 1080p', '1080p'));
  } else {
    out.add(_src(
        'https://vidsrc.stream/embed/tv/$id/${season == 0 ? 1 : season}/${episode == 0 ? 1 : episode}',
        'VidSrc SH · 720p',
        '720p'));
  }

  return out;
}

Future<List<StreamSource>> embedGetStreams(MediaDetails d,
        {int season = 0, int episode = 0}) async =>
    _build(d, season: season, episode: episode);
