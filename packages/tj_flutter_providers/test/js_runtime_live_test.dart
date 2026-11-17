// Live smoke test: runs the actual JS runtime (QuickJS-NG via quickjs_engine) with the
// real polyfill + call wrapper and a provider that exercises every bridge:
// fetch, setTimeout, crypto.subtle (SHA-256 + AES-GCM), atob/btoa, TextEncoder.
//
// Requires the native bridge library (see README §7 for LIBQUICKJSC_TEST_PATH).
// Skipped unless TJ_LIVE_TESTS=1.
//
// Run: TJ_LIVE_TESTS=1 flutter test test/js_runtime_live_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

// NOTE: no `var module = {}` preamble here — JsRuntime adds the CommonJS wrapper.
const String syntheticProvider = r'''
module.exports.getStreams = async function (tmdbId, mediaType, season, episode) {
  var out = [];
  // 1. base64 + TextEncoder
  var bytes = new TextEncoder().encode('cinezo-' + tmdbId);
  var b64 = btoa(String.fromCharCode.apply(null, Array.from(bytes)));
  out.push({ name: 'b64 ' + b64, url: 'https://example.com/a.m3u8', quality: '360p' });

  // 2. crypto.subtle digest via the Dart crypto bridge
  var digest = await crypto.subtle.digest({ name: 'SHA-256' }, bytes);
  var digestHex = Array.from(new Uint8Array(digest)).map(function (b) {
    return ('0' + b.toString(16)).slice(-2);
  }).join('');

  // 3. AES-GCM round trip via the Dart crypto bridge
  var key = await crypto.subtle.importKey('raw', new Uint8Array(32), 'AES-GCM', false, ['encrypt']);
  var iv = new Uint8Array(12);
  var enc = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: iv }, key, new TextEncoder().encode('hello world'));
  var dec = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: iv }, key, enc);
  var plain = new TextDecoder().decode(dec);

  // 4. timers via the Dart sleep bridge
  var slept = false;
  await new Promise(function (resolve) { setTimeout(function () { slept = true; resolve(); }, 30); });

  // 5. fetch via the Dart http bridge — hits the real auto-update manifest URL
  var res = await fetch('https://raw.githubusercontent.com/Skywave22/Plugins-TJ/main/manifest.json');
  // Providers read bodies through res.text() (see src/_lib/host.js), not res.body.
  var body = JSON.parse((await res.text()) || '{}');
  var scraperCount = (body.scrapers || []).length;

  out.push({
    name: 'probe ' + mediaType + ' s' + season + 'e' + episode,
    title: 'digest ' + digestHex.slice(0, 16) + ' | gcm ' + plain + ' | slept ' + slept +
        ' | status ' + res.status + ' | manifest ' + (body.name || 'n/a') + ' v' + (body.version || '') +
        ' (' + scraperCount + ' providers)' +
        ' | ua ' + (res.headers.get('content-type') || ''),
    url: 'https://example.com/b.m3u8',
    quality: '1080p',
    language: 'Hindi',
    provider: 'synthetic',
    headers: { 'Referer': 'https://example.com/' }
  });
  return out;
};
''';

void main() {
  final live = Platform.environment['TJ_LIVE_TESTS'] == '1';

  test(
    'JS runtime executes a provider through every Dart bridge',
    () async {
      final runtime = JsRuntime(
        tmdbApiKey:
            Platform.environment['TMDB_API_KEY'] ??
            '439c478a771f35c05022f9feabcca01c',
        polyfillCode: File('assets/js/polyfill.js').readAsStringSync(),
        callCode: File('assets/js/call.js').readAsStringSync(),
        cryptoJsCode: File('assets/js/crypto-js.min.js').readAsStringSync(),
      );

      final logs = <String>[];
      final json = await runtime
          .getStreamsJson(
            providerCode: syntheticProvider,
            providerId: 'synthetic',
            tmdbId: '27205',
            mediaType: 'tv',
            season: 1,
            episode: 2,
            onLog: logs.add,
          )
          .timeout(const Duration(seconds: 60));

      expect(json, isNotEmpty, reason: 'no result; logs=$logs');
      final list = (jsonDecode(json) as List).cast<Map>();
      final b64Stream = StreamResult.fromJson(
        Map<String, dynamic>.from(list.first),
      );
      final streams = StreamResult.fromJson(
        Map<String, dynamic>.from(list.last),
      );

      expect(streams.name, contains('probe tv s1e2'));
      expect(streams.title, contains('gcm hello world'));
      expect(streams.title, contains('slept true'));
      expect(streams.title, contains('status 200'));
      expect(streams.title, contains('manifest TJ-Plugins v1.'));
      expect(streams.title, contains('providers)'));
      expect(streams.headers['Referer'], 'https://example.com/');
      expect(b64Stream.name, contains('b64 '));
      runtime.dispose();
    },
    skip: live
        ? false
        : 'set TJ_LIVE_TESTS=1 to run (needs network + quickjs host lib)',
  );
}
