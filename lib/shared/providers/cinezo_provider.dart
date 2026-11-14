/// Cinezo (cinezo.gd) streaming provider.
///
/// Fetches streams from the VidNest player API (new.vidnest.fun), which returns
/// a shuffled-alphabet base64 blob. The alphabet mapping is decoded client-
/// side (no crypto needed) to reveal JSON that lists HLS/MP4 sources and
/// optional subtitle tracks.
///
/// Ported from Plugins-TJ/src/cinezo/plugin.skystream.js (vnFetch/vnDecode
/// path only — nxsha/ScreenScape backend lives in screenscape_provider.dart).
library;

import 'dart:convert';
import 'package:dio/dio.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';

const _vnApi = 'https://new.vidnest.fun';
const _vnAlpha =
    'RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

const _vnRelays = [
  'https://long-night-d802.streamed-5.workers.dev',
  'https://blue-bush-5977.streamed-7.workers.dev',
  'https://rapid-heart-03c8.streamed-4.workers.dev',
  'https://super-flower-9c85.streamed-2.workers.dev',
  'https://flat-sky-cf20.streamed-85.workers.dev',
  'https://vidrift-cf.streamed-8.workers.dev',
];

const _vnProviders = [
  _VnProv(path: 'allmovies', name: 'Lamda'),
  _VnProv(path: 'nextgencloudfabric', name: 'Zeta'),
  _VnProv(path: 'onehd', name: 'Alfa'),
  _VnProv(path: 'flixhq', name: 'Beta'),
  _VnProv(path: 'rpmvid', name: 'Prime'),
  _VnProv(path: 'vidzee', name: 'Gama'),
];

class _VnProv {
  final String path, name;
  const _VnProv({required this.path, required this.name});
}

/// Decode the VidNest shuffled-alphabet base64 into a UTF-8 string.
String _vnDecode(String data) {
  final map = <String, int>{};
  for (var i = 0; i < 64; i++) {
    map[_vnAlpha[i]] = i;
  }
  final bytes = <int>[];
  var buf = 0, bits = 0;
  for (var i = 0; i < data.length; i++) {
    final ch = data[i];
    final v = map[ch];
    if (v == null) continue; // skip '=' / junk
    buf = (buf << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((buf >> bits) & 0xFF);
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String? _qualityOf(String text) {
  final t = text;
  if (RegExp(r'\b(4k|2160p?)\b', caseSensitive: false).hasMatch(t)) return '4K';
  final m =
      RegExp(r'\b(1080|720|480|360)p?\b', caseSensitive: false).firstMatch(t);
  return m != null ? '${m[1]}p' : null;
}

int _qRank(String? q) => switch (q) {
      '4K' => 5,
      '1080p' => 4,
      '720p' => 3,
      null => 3,
      '480p' => 2,
      '360p' => 1,
      _ => 0
    };

/// Collect streams from one provider endpoint; returns null on failure.
Future<Map<String, dynamic>?> _vnFetch(
    Dio dio, _VnProv prov, String type, int id,
    {int season = 0, int episode = 0}) async {
  final path = type == 'movie'
      ? '/${prov.path}/movie/$id'
      : '/${prov.path}/tv/$id/$season/$episode';
  try {
    final r = await dio.getUri<List<int>>(
      Uri.parse(_vnApi + path),
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent': _userAgent,
          'Referer': 'https://vidnest.fun/',
          'Origin': 'https://vidnest.fun',
        },
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
      ),
    );
    if (r.statusCode != 200 || r.data == null) return null;
    final body = utf8.decode(r.data!, allowMalformed: true);
    if (body.isEmpty) return null;
    final j = jsonDecode(body);
    if (j is Map && j['encrypted'] == true && j['data'] is String) {
      final decoded = _vnDecode(j['data'] as String);
      return jsonDecode(decoded) as Map<String, dynamic>?;
    }
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null;
  }
}

/// Probe a relative /hls/... path through relays to find one returning a real playlist.
Future<String?> _viaRelay(String relPath, int startIdx) async {
  final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 7),
      receiveTimeout: const Duration(seconds: 7),
      sendTimeout: const Duration(seconds: 7),
      headers: {'User-Agent': _userAgent}));
  for (var k = 0; k < 3; k++) {
    final base = _vnRelays[(startIdx + k) % _vnRelays.length];
    try {
      final u = base + relPath;
      final r = await dio.get<String>(u);
      final body = r.data ?? '';
      if ((r.statusCode == 200 || r.statusCode == 206) &&
          body.trim().startsWith('#EXTM3U')) {
        return u;
      }
    } catch (_) {/* try next relay */}
  }
  return null;
}

Map<String, String> _cleanHeaders(Map? h) {
  final out = <String, String>{};
  if (h == null) return out;
  const skip = {
    'connection',
    'accept',
    'accept-encoding',
    'host',
    'content-length'
  };
  h.forEach((k, v) {
    final key = k.toString().trim().toLowerCase();
    if (skip.contains(key)) return;
    out[k.toString().trim()] = v.toString().trim();
  });
  if (!out.containsKey('User-Agent')) out['User-Agent'] = _userAgent;
  return out;
}

/// Unwrap VidNest /hls/&lt;base64url {u, h}&gt;/master.m3u8 style paths that encode
/// the real URL directly in the path segment.
({String url, Map<String, String> headers})? _vnUnwrap(String rel) {
  final m = RegExp(r'^\/hls\/([A-Za-z0-9_\-]+)\/').firstMatch(rel);
  if (m == null) return null;
  try {
    // The inner segment uses standard base64url (alphabet B64+/ with -_ substitutions)
    final seg = m[1]!;
    final std = seg.replaceAll('-', '+').replaceAll('_', '/');
    final padded = std + ('=' * ((4 - std.length % 4) % 4));
    final raw = base64Decode(padded);
    final j = jsonDecode(utf8.decode(raw));
    if (j is Map &&
        j['u'] is String &&
        RegExp(r'^https?:\/\/', caseSensitive: false).hasMatch(j['u'])) {
      return (url: j['u'] as String, headers: _cleanHeaders(j['h'] as Map?));
    }
  } catch (_) {}
  return null;
}

Future<List<StreamSource>> cinezoGetStreams(MediaDetails details,
    {int season = 0, int episode = 0}) async {
  final dio = Dio();
  final type = details.type == MediaType.movie ? 'movie' : 'tv';
  final results = await Future.wait(_vnProviders.map((prov) =>
      _vnFetch(dio, prov, type, details.id, season: season, episode: episode)
          .then((j) => (prov: prov, j: j))));

  final cands = <StreamSource>[];
  final relayJobs = <Future<void>>[];
  var relayIdx = DateTime.now().millisecondsSinceEpoch % _vnRelays.length;

  for (final a in results) {
    final j = a.j;
    if (j == null) continue;
    final topHeaders = _cleanHeaders(j['headers'] as Map?);

    void addOne(dynamic x) {
      if (x is! Map) return;
      final url = (x['url'] ?? '').toString();
      if (url.isEmpty) return;
      // Skip embed pages that aren't direct streams
      if (RegExp(r'\/embed[\/.]|embed\.php', caseSensitive: false)
          .hasMatch(url)) {
        return;
      }
      final lang = (x['language'] ?? '')
          .toString()
          .replaceAll(RegExp(r'^original$', caseSensitive: false), '')
          .trim();
      final qualityLabel = (x['quality'] ?? '').toString();
      final q = _qualityOf('$qualityLabel $url');
      final typeStr = (x['type'] ?? '').toString();
      final isMp4 =
          RegExp(r'mp4|mkv', caseSensitive: false).hasMatch(typeStr) ||
              RegExp(r'\.(mp4|mkv)(\?|$)', caseSensitive: false)
                  .hasMatch(url.split('?').first);
      var label = 'Cinezo · ${a.prov.name}';
      if (lang.isNotEmpty) label += ' · $lang';
      final tags = <String>[];
      if (q != null) tags.add(q);
      if (isMp4) tags.add('MP4');
      if (tags.isNotEmpty) label += ' (${tags.join(', ')})';
      final headers = _cleanHeaders((x['headers'] as Map?) ?? topHeaders);

      final src = StreamSource(
        url: url,
        name: label,
        quality: q,
        language: lang,
        headers: headers,
        providerId: 'cinezo:${a.prov.path}',
      );

      if (!RegExp(r'^https?:', caseSensitive: false).hasMatch(url)) {
        // Relative path — try to unwrap embedded URL, else probe relays
        final rel = url.startsWith('/') ? url : '/$url';
        final direct = _vnUnwrap(rel);
        if (direct != null) {
          cands.add(src.copyWith(url: direct.url, headers: direct.headers));
          return;
        }
        final start = relayIdx++;
        relayJobs.add(_viaRelay(rel, start).then((abs) {
          if (abs != null) {
            cands.add(
                src.copyWith(url: abs, headers: {'User-Agent': _userAgent}));
          }
        }));
        return;
      }
      cands.add(src);
    }

    // Collect streams from top-level URL, .streams[], .sources[], .data.stream.playlist
    if (j['url'] != null) {
      addOne({'url': j['url'], 'quality': j['quality'], 'type': j['type']});
    }
    for (final x in (j['streams'] as List? ?? const [])) {
      addOne(x);
    }
    for (final x in (j['sources'] as List? ?? const [])) {
      addOne(x);
    }
    if (j['data'] is Map) {
      final d = j['data'] as Map;
      if (d['stream'] is Map && (d['stream'] as Map)['playlist'] != null) {
        addOne({'url': (d['stream'] as Map)['playlist'], 'type': 'hls'});
      }
    }
  }

  await Future.wait(relayJobs);

  // Sort by quality rank descending, dedupe by URL
  final seen = <String>{};
  cands.sort((a, b) => _qRank(b.quality).compareTo(_qRank(a.quality)));
  final out = <StreamSource>[];
  for (final s in cands) {
    if (seen.add(s.url)) out.add(s);
  }
  return out.take(24).toList();
}
