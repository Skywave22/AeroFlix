import 'dart:convert';
import 'package:dio/dio.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';

/// Resolves real HLS (m3u8) URLs from the user-specified embed providers
/// (VidSrc MOV, VidSrc PK, AutoEmbed, VidSpark, VidSrc SH). These hosts
/// serve an HTML iframe page — we have to call their internal JSON APIs to
/// fetch the actual playlist URL, then build the final m3u8 URL (which is
/// usually XOR/RC4-encoded per source).
///
/// Every resolver returns an empty list on failure; StreamService will fall
/// back to the next provider. No demo sources are shipped.

final List<EmbedResolver> resolvers = [
  _VidSrcToResolver(), // most reliable (used by vidsrc.pk, autoembed too)
  _VidSrcXyzResolver(), // vidsrc MOV / vidsrc.xyz
  _VidSrcStreamResolver(), // vidsrc SH / vidsrc.stream
  _VidSparkResolver(),
];

abstract class EmbedResolver {
  String get label;
  String get quality;
  Future<List<StreamSource>> resolve(Dio dio, MediaDetails d,
      {int season, int episode});
}

String _tvPath(MediaDetails d, int s, int e) {
  if (d.type == MediaType.tv) {
    final ss = s == 0 ? 1 : s;
    final ee = e == 0 ? 1 : e;
    return '/tv/${d.id}/$ss-$ee';
  }
  return '/movie/${d.id}';
}

// ---------- VidSrc.to (VidSrc PK family / 2embed / vidsrc.pm/pk) ----------
class _VidSrcToResolver extends EmbedResolver {
  @override
  String get label => 'VidSrc';
  @override
  String get quality => '1080p';

  static const _base = 'https://vidsrc.to';

  @override
  Future<List<StreamSource>> resolve(Dio dio, MediaDetails d,
      {int season = 0, int episode = 0}) async {
    try {
      final embedPath = d.type == MediaType.tv
          ? '/embed/tv/${d.id}/${season == 0 ? 1 : season}/${episode == 0 ? 1 : episode}'
          : '/embed/movie/${d.id}';
      final r = await dio.get('$_base$embedPath',
          options: Options(headers: {'Referer': '$_base/'}));
      final html = r.data.toString();
      // data-id="xxxx"
      final m = RegExp(r'data-id="([^"]+)"').firstMatch(html);
      if (m == null) return const [];
      final dataId = m.group(1)!;
      final provR = await dio.get(
          '$_base/ajax/embed/episode/$dataId/sources',
          options: Options(headers: {'Referer': '$_base$embedPath', 'x-requested-with': 'XMLHttpRequest'}));
      final prov = (provR.data as Map<String, dynamic>);
      final result = (prov['result'] as List?) ?? const [];
      final out = <StreamSource>[];
      for (final s in result) {
        final id = s['id']?.toString() ?? '';
        final title = s['title']?.toString() ?? '';
        if (id.isEmpty) continue;
        try {
          final srcR = await dio.get('$_base/ajax/embed/source/$id',
              options: Options(headers: {
                'Referer': '$_base$embedPath',
                'x-requested-with': 'XMLHttpRequest'
              }));
          final srcData = srcR.data as Map<String, dynamic>;
          final url = srcData['url']?.toString() ?? '';
          if (url.isEmpty) continue;
          final decoded = _decodeVidSrc(url);
          if (decoded == null || decoded.isEmpty) continue;
          out.add(StreamSource(
            url: decoded,
            name: 'VidSrc · $title',
            quality: quality,
            providerId: 'vidsrc:$title',
            headers: {'Referer': '$_base/'},
          ));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // VidSrc.to uses a simple substitution cipher + base64.
  // Implementation matches the open-source vidb3play decoder.
  String? _decodeVidSrc(String encodedUrl) {
    try {
      final key = '8z5Ag5wgagfsOuhz'; // VidSrc standard key
      final replaced = encodedUrl
          .replaceAll('_', '/')
          .replaceAll('-', '+');
      final buffer = base64.decode(
          base64.normalize(replaced + '=' * ((4 - replaced.length % 4) % 4)));
      final k = key.codeUnits;
      final out = <int>[];
      for (var i = 0; i < buffer.length; i++) {
        out.add(buffer[i] ^ k[i % k.length] ^ 56);
      }
      final decoded = utf8.decode(out, allowMalformed: true);
      // Decoded is usually a JSON string containing {"url":"..."}
      final mm = RegExp(r'"url":"([^"]+)"').firstMatch(decoded);
      if (mm != null) return mm.group(1)!.replaceAll(r'\/', '/');
      // Or just a plain URL
      if (decoded.startsWith('http')) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }
}

// ---------- VidSrc XYZ (vidsrc.xyz / MOV) ----------
class _VidSrcXyzResolver extends EmbedResolver {
  @override
  String get label => 'VidSrc MOV';
  @override
  String get quality => '720p';

  static const _base = 'https://vidsrc.xyz';

  @override
  Future<List<StreamSource>> resolve(Dio dio, MediaDetails d,
      {int season = 0, int episode = 0}) async {
    try {
      // vidsrc.xyz serves an iframe whose <script> includes a direct m3u8 via
      // the /ajax/embed/info_getSources endpoint keyed by the IMDb/TMDB id.
      // Easier: it exposes /<movie|tv>/<id>_main.m3u8 on the CDN for many titles.
      final suffix = d.type == MediaType.tv
          ? '${d.id}/${season == 0 ? 1 : season}/${episode == 0 ? 1 : episode}'
          : '${d.id}';
      final url = d.type == MediaType.tv
          ? '$_base/tv/$suffix.m3u8'
          : '$_base/movie/$suffix.m3u8';
      try {
        final r = await dio.head(url,
            options: Options(headers: {'Referer': '$_base/'}));
        if (r.statusCode == 200) {
          return [
            StreamSource(
                url: url,
                name: 'VidSrc MOV · 720p',
                quality: '720p',
                providerId: 'vidsrc-mov',
                headers: {'Referer': '$_base/'})
          ];
        }
      } catch (_) {}
      return const [];
    } catch (_) {
      return const [];
    }
  }
}

// ---------- VidSrc SH / vidsrc.stream ----------
class _VidSrcStreamResolver extends EmbedResolver {
  @override
  String get label => 'VidSrc SH';
  @override
  String get quality => '720p';

  static const _base = 'https://vidsrc.stream';

  @override
  Future<List<StreamSource>> resolve(Dio dio, MediaDetails d,
      {int season = 0, int episode = 0}) async {
    try {
      // vidsrc.stream hosts embed/<movie|tv>/<id>/s/e which references
      // a player on vidply.to with a direct /m3u8/<encoded>.
      final url = d.type == MediaType.tv
          ? '$_base/embed/tv/${d.id}/${season == 0 ? 1 : season}/${episode == 0 ? 1 : episode}'
          : '$_base/embed/movie/${d.id}';
      final r = await dio.get(url,
          options: Options(headers: {'Referer': '$_base/'}));
      final html = r.data.toString();
      // Look for file:"https://...m3u8" or source: "https://..."
      final m = RegExp("(file|source)\\s*:\\s*[\"'](https?://[^\"']+\\.m3u8[^\"']*)[\"']")
          .firstMatch(html);
      if (m == null) return const [];
      final m3u = m.group(2)!;
      return [
        StreamSource(
            url: m3u,
            name: 'VidSrc SH · 720p',
            quality: '720p',
            providerId: 'vidsrc-sh',
            headers: {'Referer': '$_base/'})
      ];
    } catch (_) {
      return const [];
    }
  }
}

// ---------- VidSpark ----------
class _VidSparkResolver extends EmbedResolver {
  @override
  String get label => 'VidSpark';
  @override
  String get quality => '720p';

  static const _base = 'https://vidspark.cc';

  @override
  Future<List<StreamSource>> resolve(Dio dio, MediaDetails d,
      {int season = 0, int episode = 0}) async {
    try {
      final url = d.type == MediaType.tv
          ? '$_base/embed/tv?tmdb=${d.id}&season=${season == 0 ? 1 : season}&episode=${episode == 0 ? 1 : episode}'
          : '$_base/embed/movie?tmdb=${d.id}';
      final r = await dio.get(url,
          options: Options(headers: {'Referer': '$_base/'}));
      final html = r.data.toString();
      final m = RegExp("file\\s*:\\s*[\"'](https?://[^\"']+\\.m3u8[^\"']*)[\"']")
          .firstMatch(html);
      if (m == null) return const [];
      return [
        StreamSource(
            url: m.group(1)!,
            name: 'VidSpark · 720p',
            quality: '720p',
            providerId: 'vidspark',
            headers: {'Referer': '$_base/'})
      ];
    } catch (_) {
      return const [];
    }
  }
}

Future<List<StreamSource>> embedGetStreams(Dio dio, MediaDetails d,
    {int season = 0, int episode = 0}) async {
  final results = await Future.wait(resolvers.map((r) => r
      .resolve(dio, d, season: season, episode: episode)
      .timeout(const Duration(seconds: 12),
          onTimeout: () => const <StreamSource>[])));
  return results.expand((x) => x).toList();
}
