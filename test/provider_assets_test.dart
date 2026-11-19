import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

/// Guards the two asset paths that silently break playback when they drift:
///
/// 1. the JS runtime the package executes providers with (`packages/<pkg>/…`,
///    which is *not* the same path as inside the package's own repo), and
/// 2. the bundled provider snapshot the app seeds itself from on first launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('runtime JS assets', () {
    for (final path in [
      'assets/js/polyfill.js',
      'assets/js/call.js',
      'assets/js/crypto-js.min.js',
    ]) {
      test('$path loads from the package namespace', () async {
        final code =
            await rootBundle.loadString('packages/tj_flutter_providers/$path');
        expect(code, isNotEmpty);
      });
    }
  });

  group('bundled providers', () {
    test('manifest parses and lists the recommended pack', () async {
      final raw = await rootBundle.loadString('assets/providers/manifest.json');
      final manifest =
          Manifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);

      expect(manifest.scrapers, isNotEmpty);
      for (final id in ProviderManager.recommendedIds) {
        expect(manifest.byId(id), isNotNull,
            reason: '$id is enabled by default but missing from the manifest');
      }
    });

    test('every provider in the manifest has a bundled bundle', () async {
      final raw = await rootBundle.loadString('assets/providers/manifest.json');
      final manifest =
          Manifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);

      for (final provider in manifest.scrapers) {
        final code =
            await rootBundle.loadString('assets/providers/${provider.id}.js');
        expect(code, contains('getStreams'),
            reason: '${provider.id}.js is not a provider bundle');
      }
    });
  });
}
