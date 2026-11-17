// Live end-to-end test against a REAL Plugins-TJ provider bundle.
//
// Point TJ_PROVIDER_DIR at a checkout of https://github.com/Skywave22/Plugins-TJ
// (its providers/ folder) and run:
//
//   TJ_PROVIDER_DIR=/path/to/Plugins-TJ/providers \
//   TJ_PROVIDER=cinezo TJ_TMDB_ID=27205 TJ_MEDIA_TYPE=movie \
//   flutter test test/real_provider_live_test.dart --timeout 180s
//
// Optional: TJ_SEASON / TJ_EPISODE for series.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

void main() {
  final providerDir = Platform.environment['TJ_PROVIDER_DIR'];
  final providerId = Platform.environment['TJ_PROVIDER'] ?? 'cinezo';
  final tmdbId = Platform.environment['TJ_TMDB_ID'] ?? '27205';
  final mediaType = Platform.environment['TJ_MEDIA_TYPE'] ?? 'movie';
  final season = int.tryParse(Platform.environment['TJ_SEASON'] ?? '');
  final episode = int.tryParse(Platform.environment['TJ_EPISODE'] ?? '');

  test(
    'real provider returns playable streams',
    () async {
      final code = File('$providerDir/$providerId.js').readAsStringSync();
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
            providerCode: code,
            providerId: providerId,
            tmdbId: tmdbId,
            mediaType: mediaType,
            season: season,
            episode: episode,
            onLog: logs.add,
          )
          .timeout(const Duration(seconds: 120));

      final raw = jsonDecode(json) as List;
      final streams = raw
          .cast<Map>()
          .map((e) => StreamResult.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.url.isNotEmpty)
          .toList();

      // Surfaced for humans reading the test output.
      // ignore: avoid_print
      print(
        '$providerId -> ${streams.length} stream(s)${logs.isEmpty ? '' : ' | logs: ${logs.take(3)}'}',
      );
      for (final s in streams.take(5)) {
        // ignore: avoid_print
        print(
          '  ${s.name} [${s.quality} ${s.language ?? ''}] ${s.url.substring(0, s.url.length.clamp(0, 90))}',
        );
      }

      expect(
        streams,
        isNotEmpty,
        reason: 'provider returned no streams; logs=$logs',
      );
      expect(streams.every((s) => s.url.startsWith('http')), isTrue);
      expect(streams.first.name, isNotEmpty);
      runtime.dispose();
    },
    skip: providerDir == null
        ? 'set TJ_PROVIDER_DIR to a Plugins-TJ/providers folder to run'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
