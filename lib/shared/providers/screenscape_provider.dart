/// ScreenScape (nxsha) streaming provider.
///
/// Uses the https://web.nxsha.app JSON API. Payloads are AES-CBC encrypted
/// with CryptoJS defaults (passphrase-based OpenSSL EVP_BytesToKey, random
/// 8-byte salt) using key "S8x!Jk4ZP1uG8$my", then base64url-encoded into
/// the ?q= query parameter. Responses carry the ciphertext in _hash.
///
/// Ported from TheNexvion/decryptor/src/extractors/nxsha.js.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';

const _nxshaApi = 'https://web.nxsha.app';
const _nxshaPassphrase = 'S8x!Jk4ZP1uG8\$my';
const _nxshaUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

// ---------- CryptoJS-compatible AES passphrase encryption ----------
// Format: "Salted__" <8-byte salt> <ciphertext> (base64 in transit).

Uint8List _evpBytesToKey(List<int> pw, List<int> salt) {
  // Classic OpenSSL EVP_BytesToKey with MD5, 1 round, 32-byte key + 16-byte IV.
  final out = <int>[];
  List<int> block = const [];
  while (out.length < 48) {
    final h = md5.convert([...block, ...pw, ...salt]);
    block = h.bytes;
    out.addAll(block);
  }
  return Uint8List.fromList(out);
}

String _nxEncrypt(String plaintext) {
  final rand = Random.secure();
  final salt =
      Uint8List.fromList(List<int>.generate(8, (_) => rand.nextInt(256)));
  final pw = Uint8List.fromList(utf8.encode(_nxshaPassphrase));
  final dk = _evpBytesToKey(pw, salt);
  final key = Key(Uint8List.fromList(dk.sublist(0, 32)));
  final iv = IV(Uint8List.fromList(dk.sublist(32, 48)));
  final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
  final ct = encrypter.encrypt(plaintext, iv: iv).bytes;
  // OpenSSL container: "Salted__" + salt + ct
  final container = Uint8List.fromList([
    ...utf8.encode('Salted__'),
    ...salt,
    ...ct,
  ]);
  return base64.encode(container);
}

String? _nxDecrypt(String b64cipher) {
  if (b64cipher.isEmpty) return null;
  try {
    final raw = Uint8List.fromList(base64.decode(b64cipher));
    if (raw.length < 32) return null;
    final header = utf8.decode(raw.sublist(0, 8), allowMalformed: true);
    if (header != 'Salted__') return null;
    final salt = Uint8List.fromList(raw.sublist(8, 16));
    final ct = Uint8List.fromList(raw.sublist(16));
    final pw = Uint8List.fromList(utf8.encode(_nxshaPassphrase));
    final dk = _evpBytesToKey(pw, salt);
    final key = Key(Uint8List.fromList(dk.sublist(0, 32)));
    final iv = IV(Uint8List.fromList(dk.sublist(32, 48)));
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
    return encrypter.decrypt(Encrypted(ct), iv: iv);
  } catch (_) {
    return null;
  }
}

String _b64urlEncode(String s) =>
    s.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
String _b64urlDecode(String s) {
  var pad = s;
  pad = pad.replaceAll('-', '+').replaceAll('_', '/');
  while (pad.length % 4 != 0) {
    pad += '=';
  }
  return pad;
}

// ---------- API ----------

String _randSalt() {
  final r = Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
}

Future<Map<String, dynamic>?> _nxApi(String path, Map<String, dynamic> payload,
    {int timeoutSec = 12}) async {
  final dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: timeoutSec),
      receiveTimeout: Duration(seconds: timeoutSec),
      sendTimeout: Duration(seconds: timeoutSec)));
  final body = {
    ...payload,
    '_req_ts': DateTime.now().millisecondsSinceEpoch,
    '_req_salt': _randSalt(),
  };
  final q = _b64urlEncode(_nxEncrypt(jsonEncode(body)));
  try {
    final r = await dio.get('$_nxshaApi$path',
        queryParameters: {'q': q},
        options: Options(headers: {
          'User-Agent': _nxshaUa,
          'Accept': '*/*',
          'Referer': '$_nxshaApi/',
        }));
    if (r.statusCode != 200) return null;
    final data = r.data;
    if (data is! Map) return null;
    final hash = data['_hash']?.toString();
    if (hash == null) return null;
    final dec = _nxDecrypt(_b64urlDecode(hash));
    if (dec == null) return null;
    final obj = jsonDecode(dec);
    if (obj is Map<String, dynamic>) return obj;
    return null;
  } catch (_) {
    return null;
  }
}

String? _qOf(String label, String url) {
  final hay = '$label $url';
  if (RegExp(r'\b(4k|2160p?)\b', caseSensitive: false).hasMatch(hay)) {
    return '4K';
  }
  final m =
      RegExp(r'\b(1080|720|480|360)p?\b', caseSensitive: false).firstMatch(hay);
  return m != null ? '${m[1]}p' : null;
}

Future<List<StreamSource>> nxshaGetStreams(MediaDetails details,
    {int season = 0, int episode = 0}) async {
  final type = details.type == MediaType.movie ? 'movie' : 'tv';
  final servers = await _nxApi(
      '/api/servers',
      {
        'tmdbId': details.id.toString(),
        'type': type,
        'imdb_id': '',
        'season': season == 0 ? '1' : season.toString(),
        'episode': episode == 0 ? '1' : episode.toString(),
        'method': 'stream',
      },
      timeoutSec: 10);
  if (servers == null) return const [];
  final serverList =
      (servers['servers'] as List? ?? const []).cast<Map<String, dynamic>>();
  if (serverList.isEmpty) return const [];

  final futures = serverList.take(12).map((s) async {
    final provId = (s['scraper'] ?? s['id'] ?? '').toString();
    final name = (s['name'] ?? provId).toString();
    if (provId.isEmpty) return null;
    final srcRes = await _nxApi(
        '/api/sources',
        {
          'provider': provId,
          'tmdbId': details.id.toString(),
          'imdb_id': '',
          'type': type,
          'season': season == 0 ? '1' : season.toString(),
          'episode': episode == 0 ? '1' : episode.toString(),
          'method': 'stream',
        },
        timeoutSec: 10);
    if (srcRes == null) return null;
    final sources =
        (srcRes['sources'] as List? ?? const []).cast<Map<String, dynamic>>();
    // Prefer m3u8 direct, then mp4 direct, skip embeds
    Map<String, dynamic>? chosen;
    for (final s2 in sources) {
      final ty = (s2['type'] ?? '').toString().toLowerCase();
      final isEmbed = (s2['isEmbed'] == true);
      if (!isEmbed && ty == 'm3u8') {
        chosen = s2;
        break;
      }
    }
    chosen ??= sources.firstWhere(
        (s2) =>
            s2['isEmbed'] != true &&
            (s2['type'] ?? '').toString().toLowerCase() == 'mp4',
        orElse: () => <String, dynamic>{});
    if (chosen.isEmpty) return null;
    final url = (chosen['url'] ?? '').toString();
    if (url.isEmpty ||
        !RegExp(r'^https?:', caseSensitive: false).hasMatch(url)) {
      return null;
    }
    final q =
        _qOf('${chosen['quality'] ?? ''} ${chosen['label'] ?? ''} $name', url);
    final headers = <String, String>{'User-Agent': _nxshaUa};
    final srcHeaders = chosen['headers'];
    if (srcHeaders is Map) {
      srcHeaders.forEach((k, v) {
        headers[k.toString()] = v.toString();
      });
    }
    var label = 'ScreenScape · $name';
    if (q != null) label += ' ($q)';
    // workers.dev URLs require nxsha origin/referer
    if (RegExp(r'workers\.dev', caseSensitive: false).hasMatch(url)) {
      headers['Referer'] = '$_nxshaApi/';
      headers['Origin'] = _nxshaApi;
    }
    return StreamSource(
      url: url,
      name: label,
      quality: q,
      headers: headers,
      providerId: 'screenscape:$provId',
    );
  });

  final results = await Future.wait(futures);
  final out = results.whereType<StreamSource>().toList();
  // Dedup by URL, sort by quality
  final seen = <String>{};
  out.sort((a, b) => _nxQ(b.quality).compareTo(_nxQ(a.quality)));
  return out.where((s) => seen.add(s.url)).take(20).toList();
}

int _nxQ(String? q) => switch (q) {
      '4K' => 5,
      '1080p' => 4,
      '720p' => 3,
      null => 3,
      '480p' => 2,
      '360p' => 1,
      _ => 0
    };
