import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

/// Covers the offline half of the provider pipeline: the app ships provider
/// bundles in `assets/providers/`, and [ProviderManager.seedBundled] copies
/// them to app storage so a first launch with no GitHub access still resolves
/// streams.
void main() {
  late Directory dir;
  late ProviderManager manager;

  const manifestJson = '''
{"name":"TJ-Plugins","version":"1.0.72","scrapers":[
 {"id":"cinezo","name":"Cinezo","version":"1.0.12","filename":"providers/cinezo.js"},
 {"id":"nxsha","name":"Nxsha","version":"1.0.3","filename":"providers/nxsha.js"}
]}
''';

  Manifest manifest() =>
      Manifest.fromJson(jsonDecode(manifestJson) as Map<String, dynamic>);

  Future<String?> bundled(String id) async =>
      'function getStreams() { return []; } // $id';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tj_seed');
    manager = ProviderManager(cacheDir: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('bundled seed installs providers when nothing is cached', () async {
    final seeded = await manager.seedBundled(
      manifest: manifest(),
      read: bundled,
    );
    expect(seeded, 2);

    final cached = await manager.getCached();
    expect(cached.keys, containsAll(['cinezo', 'nxsha']));
    expect(cached['cinezo']!.version, '1.0.12');
    expect(await manager.readProviderCode('cinezo'), contains('getStreams'));
  });

  test('bundled seed never downgrades a newer download', () async {
    await manager.seedBundled(manifest: manifest(), read: bundled);

    // Simulate an upstream auto-update that already landed on the device.
    final file = await manager.providerFile('cinezo');
    await file.writeAsString('function getStreams() { return ["new"]; }');
    final cached = await manager.getCached();
    cached['cinezo'] = CachedProvider(
      id: 'cinezo',
      version: '1.0.99',
      filePath: file.path,
      downloadedAt: DateTime.now(),
      sizeBytes: await file.length(),
    );
    await File('${dir.path}/meta.json').writeAsString(
      jsonEncode(cached.map((k, v) => MapEntry(k, v.toJson()))),
    );

    final seededAgain = await manager.seedBundled(
      manifest: manifest(),
      read: bundled,
    );
    expect(seededAgain, 0, reason: 'nobody is older than the bundled seed');
    expect(await manager.readProviderCode('cinezo'), contains('"new"'));
  });

  test('manifest is cached for offline use', () async {
    await manager.cacheManifestJson(manifestJson);
    final cached = await manager.getCachedManifest();
    expect(cached, isNotNull);
    expect(cached!.scrapers.length, 2);
    expect(cached.byId('nxsha')?.version, '1.0.3');
  });

  test('mirror list starts with GitHub raw and falls back to jsDelivr', () {
    expect(ProviderManager.defaultMirrorBases.first,
        ProviderManager.defaultBaseUrl);
    expect(
        ProviderManager.defaultMirrorBases
            .any((m) => m.contains('cdn.jsdelivr.net')),
        isTrue);
  });
}
