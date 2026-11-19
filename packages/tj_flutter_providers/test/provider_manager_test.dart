import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

String _sampleStream = jsonEncode({
  'name': 'Cinezo · Scape Nitro - Hindi · English',
  'title': 'Inception (2010)',
  'url': 'https://wts.itsnitrox.tech/pitro/abc/master.m3u8',
  'quality': '1080p',
  'provider': 'cinezo',
  'language': 'Hindi + English',
  'size': '1.2 GB',
  'headers': {'Referer': 'https://cinezo.example/', 'User-Agent': 'UA'},
  'subtitles': [
    {'url': 'https://subs.example/en.vtt', 'language': 'English'},
  ],
});

void main() {
  group('Manifest parsing (real Plugins-TJ manifest)', () {
    late Manifest manifest;

    setUpAll(() {
      final raw = File('test/fixtures/manifest.json').readAsStringSync();
      manifest = Manifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    });

    test('parses repo version and all scrapers', () {
      expect(manifest.version, isNotEmpty);
      expect(manifest.scrapers.length, greaterThanOrEqualTo(20));
    });

    test('every scraper has the fields the runtime needs', () {
      for (final p in manifest.scrapers) {
        expect(p.id, isNotEmpty, reason: 'id missing');
        expect(p.name, isNotEmpty, reason: '${p.id}: name missing');
        expect(
          p.version,
          matches(RegExp(r'^\d+\.\d+\.\d+')),
          reason: '${p.id}: bad version',
        );
        expect(p.filename, 'providers/${p.id}.js', reason: '${p.id}: filename');
        expect(p.supportedTypes, isNotEmpty, reason: '${p.id}: supportedTypes');
        expect(
          p.contentLanguage,
          isNotEmpty,
          reason: '${p.id}: contentLanguage',
        );
      }
    });

    test('recommended starter pack exists in the manifest', () {
      for (final id in ProviderManager.recommendedIds) {
        expect(manifest.byId(id), isNotNull, reason: 'missing provider: $id');
      }
    });

    test('manifest round-trips through toJson', () {
      final again = ProviderInfo.fromJson(manifest.scrapers.first.toJson());
      expect(again.id, manifest.scrapers.first.id);
      expect(again.version, manifest.scrapers.first.version);
    });
  });

  group('StreamResult parsing (provider getStreams output)', () {
    test('parses a full stream object', () {
      final s = StreamResult.fromJson(
        jsonDecode(_sampleStream) as Map<String, dynamic>,
      );
      expect(s.name, contains('Cinezo'));
      expect(s.quality, '1080p');
      expect(s.provider, 'cinezo');
      expect(s.headers['Referer'], 'https://cinezo.example/');
      expect(s.subtitles.single.language, 'English');
      expect(s.isHls, isTrue);
    });

    test('tolerates missing optional fields', () {
      final s = StreamResult.fromJson({'url': 'https://x/y.mp4', 'name': 'X'});
      expect(s.url, 'https://x/y.mp4');
      expect(s.quality, 'Auto');
      expect(s.headers, isEmpty);
      expect(s.subtitles, isEmpty);
      expect(s.isMp4, isTrue);
    });

    test('coerces non-string header values and drops nested ones', () {
      final s = StreamResult.fromJson({
        'url': 'https://x/y.m3u8',
        'headers': {
          'A': 1,
          'B': true,
          'C': {'nested': 1},
        },
      });
      expect(s.headers, {'A': '1', 'B': 'true'});
    });
  });

  group('ProviderManager auto-update', () {
    late Directory tempDir;
    late String manifestBody;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('tj_test_');
      manifestBody = File('test/fixtures/manifest.json').readAsStringSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    ProviderManager buildManager({
      Map<String, String>? overrides,
      List<String>? requested,
    }) {
      final client = MockClient((request) async {
        requested?.add(request.url.toString());
        final path = request.url.path;
        if (path.endsWith('manifest.json')) {
          final body = overrides?['manifest.json'] ?? manifestBody;
          return http.Response(
            body,
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final id = path.split('/').last.replaceAll('.js', '');
        final body =
            overrides?[id] ??
            'var module={exports:{}};function getStreams(){return [];}\n// $id';
        return http.Response(body, 200);
      });
      return ProviderManager(
        baseUrl: 'https://raw.example.com/main',
        httpClient: client,
        cacheDir: tempDir,
      );
    }

    test('first sync downloads only the requested providers', () async {
      final manager = buildManager();
      final result = await manager.syncProviders(onlyIds: ['cinezo', 'nxsha']);

      expect(
        result.available.map((e) => e.id),
        containsAll(['cinezo', 'nxsha']),
      );
      final cached = await manager.getCached();
      expect(cached.keys, unorderedEquals(['cinezo', 'nxsha']));
      expect(await manager.readProviderCode('cinezo'), contains('getStreams'));
      expect(File('${tempDir.path}/cinezo.js').existsSync(), isTrue);
    });

    test('second sync with same manifest downloads nothing', () async {
      final manager = buildManager();
      await manager.syncProviders(onlyIds: ['cinezo']);

      final requested = <String>[];
      final manager2 = buildManager(requested: requested);
      final result = await manager2.syncProviders(onlyIds: ['cinezo']);

      expect(result.updatesAvailable, isEmpty);
      expect(requested.where((u) => u.endsWith('.js')), isEmpty);
    });

    test(
      'detects a version bump and re-downloads just that provider',
      () async {
        final manager = buildManager();
        await manager.syncProviders(onlyIds: ['cinezo', 'nxsha']);

        // Bump cinezo version in the remote manifest
        final doc = jsonDecode(manifestBody) as Map<String, dynamic>;
        for (final s in (doc['scrapers'] as List)) {
          if (s['id'] == 'cinezo') s['version'] = '99.0.1';
        }
        final requested = <String>[];
        final manager2 = buildManager(
          overrides: {
            'manifest.json': jsonEncode(doc),
            'cinezo': '// updated cinezo\ngetStreams = 1;',
          },
          requested: requested,
        );
        final result = await manager2.syncProviders(
          onlyIds: ['cinezo', 'nxsha'],
        );

        expect(result.updatesAvailable.map((e) => e.id), ['cinezo']);
        expect(requested.where((u) => u.endsWith('cinezo.js')).length, 1);
        expect(requested.where((u) => u.endsWith('nxsha.js')), isEmpty);
        expect(
          await manager2.readProviderCode('cinezo'),
          contains('updated cinezo'),
        );
        final cached = await manager2.getCached();
        expect(cached['cinezo']!.version, '99.0.1');
      },
    );

    test('download failure keeps the old cached provider usable', () async {
      final manager = buildManager();
      await manager.syncProviders(onlyIds: ['cinezo']);
      final before = await manager.readProviderCode('cinezo');

      final failing = ProviderManager(
        baseUrl: 'https://raw.example.com/main',
        cacheDir: tempDir,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('manifest.json')) {
            final doc = jsonDecode(manifestBody) as Map<String, dynamic>;
            for (final s in (doc['scrapers'] as List)) {
              if (s['id'] == 'cinezo') s['version'] = '99.0.1';
            }
            return http.Response.bytes(
              utf8.encode(jsonEncode(doc)),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('not found', 404);
        }),
      );
      final result = await failing.syncProviders(onlyIds: ['cinezo']);
      expect(result.updatesAvailable.map((e) => e.id), ['cinezo']);

      expect(await failing.readProviderCode('cinezo'), before);
      expect((await failing.getCached())['cinezo']!.version, isNot('99.0.1'));
    });

    test('manifest cached for offline use', () async {
      final manager = buildManager();
      await manager.fetchManifest();
      final cachedManifest = await manager.getCachedManifest();
      expect(cachedManifest, isNotNull);
      expect(
        cachedManifest!.scrapers.length,
        Manifest.fromJson(jsonDecode(manifestBody) as Map<String, dynamic>)
            .scrapers
            .length,
      );
    });

    test('provider removed upstream is deleted locally', () async {
      final manager = buildManager();
      await manager.syncProviders(onlyIds: ['cinezo', 'nxsha']);

      final doc = jsonDecode(manifestBody) as Map<String, dynamic>;
      doc['scrapers'] = (doc['scrapers'] as List)
          .where((s) => s['id'] != 'nxsha')
          .toList();
      final manager2 = buildManager(
        overrides: {'manifest.json': jsonEncode(doc)},
      );
      final result = await manager2.syncProviders(onlyIds: ['cinezo', 'nxsha']);

      expect(result.removedIds, contains('nxsha'));
      expect(File('${tempDir.path}/nxsha.js').existsSync(), isFalse);
      expect((await manager2.getCached()).containsKey('nxsha'), isFalse);
    });

    test('version comparison handles differing segment counts', () async {
      final manager = buildManager();
      expect(await manager.getCached(), isEmpty);
      // 1.0.10 > 1.0.9 and 1.2 > 1.1.9 (exercise via checkForUpdates flow)
      final doc = jsonDecode(manifestBody) as Map<String, dynamic>;
      for (final s in (doc['scrapers'] as List)) {
        if (s['id'] == 'cinezo') s['version'] = '1.0.10';
        if (s['id'] == 'nxsha') s['version'] = '2';
      }
      final manager2 = buildManager(
        overrides: {'manifest.json': jsonEncode(doc)},
      );
      await manager2.syncProviders(onlyIds: ['cinezo', 'nxsha']);

      final cached = await manager2.getCached();
      expect(cached['cinezo']!.version, '1.0.10');
      final result = await manager2.checkForUpdates();
      expect(result.updatesAvailable.map((e) => e.id), isEmpty);
    });
  });

  group('ProviderService', () {
    test('returns empty list when provider is not downloaded yet', () async {
      final tempDir = Directory.systemTemp.createTempSync('tj_svc_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final manager = ProviderManager(
        cacheDir: tempDir,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final service = ProviderService(
        manager: manager,
        tmdbApiKey: 'test',
        enabledIds: const ['cinezo', 'nxsha'],
      );

      final streams = await service.getStreams(
        tmdbId: '27205',
        mediaType: 'movie',
      );
      expect(streams, isEmpty);
    });

    test('offline sync falls back to cached manifest', () async {
      final tempDir = Directory.systemTemp.createTempSync('tj_svc_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // Seed a cached manifest
      File('${tempDir.path}/manifest.json').writeAsStringSync(
        File('test/fixtures/manifest.json').readAsStringSync(),
      );

      final offline = ProviderManager(
        cacheDir: tempDir,
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
      );
      final service = ProviderService(
        manager: offline,
        tmdbApiKey: 'test',
        enabledIds: const ['cinezo'],
      );
      final result = await service.syncOnLaunch();
      expect(result.manifest.scrapers, isNotEmpty);
    });
  });
}
