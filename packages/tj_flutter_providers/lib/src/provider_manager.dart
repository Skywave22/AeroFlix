import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Downloads + caches TJ-Plugins providers from GitHub with auto-update.
///
/// How auto-update works (no Play Store update needed):
///  1. Fetch https://raw.githubusercontent.com/Skywave22/Plugins-TJ/main/manifest.json
///  2. Compare each provider's `version` in the manifest with the version
///     stored in `<appDocs>/tj_providers/meta.json` from the last download.
///  3. If manifest version is newer (or provider not downloaded yet),
///     download `providers/<id>.js` from the same GitHub raw base URL,
///     overwrite the cached file, and update meta.json.
///  4. Call [checkForUpdates] on app start (or on pull-to-refresh in UI).
///     If [autoUpdate] is true, download changed providers immediately.
///     If false, return [UpdateCheckResult] so UI can show "Update available".
///
/// The provider JS files are usually fetched at runtime, so a fix published in
/// the repo reaches users on the next launch without shipping a new app
/// version (this is how Nuvio's Settings → Plugins works). Because
/// raw.githubusercontent.com is slow or blocked on some mobile networks, the
/// manager also accepts **bundled seed copies** ([seedBundled]) and falls back
/// across several mirrors ([mirrorBases]) — the app therefore still resolves
/// streams on a first launch with no usable GitHub access.
class ProviderManager {
  /// Base URL of the repo on GitHub (raw). Manifest lives at "$base/manifest.json",
  /// provider files at `"$base/<filename>"` e.g. "$base/providers/cinezo.js".
  static const String defaultBaseUrl =
      'https://raw.githubusercontent.com/Skywave22/Plugins-TJ/main';

  /// Mirrors tried in order when fetching the manifest / provider files.
  /// jsDelivr is a CDN that stays reachable on networks where GitHub raw is
  /// blocked (e.g. several Indian ISPs).
  static const List<String> defaultMirrorBases = [
    'https://raw.githubusercontent.com/Skywave22/Plugins-TJ/main',
    'https://cdn.jsdelivr.net/gh/Skywave22/Plugins-TJ@main',
    'https://raw.githack.com/Skywave22/Plugins-TJ/main',
  ];

  /// Recommended starter pack (best coverage, Hindi-first).
  /// Cinezo + ScreenScape + Nxsha cover most popular titles,
  /// AniHype for anime, KatDrama for K-dramas.
  static const List<String> recommendedIds = [
    'cinezo',
    'screenscape',
    'nxsha',
    'anihype',
    'katdrama',
  ];

  /// Preferred base URL. Mirrors are tried in order starting from this one.
  final String baseUrl;

  /// All mirrors to try, in order.
  final List<String> mirrorBases;

  final http.Client _http;
  final Duration httpTimeout;

  /// Mirror that last answered successfully (used for provider downloads).
  String? _resolvedBase;

  /// Optional cache directory override (used by tests, or if you want the
  /// providers stored in a custom location instead of app documents).
  final Directory? cacheDir;

  ProviderManager({
    this.baseUrl = defaultBaseUrl,
    List<String>? mirrorBases,
    http.Client? httpClient,
    this.httpTimeout = const Duration(seconds: 20),
    this.cacheDir,
  }) : _http = httpClient ?? http.Client(),
       mirrorBases = mirrorBases ?? defaultMirrorBases;

  /// Base URL that last worked, if any.
  String? get resolvedBaseUrl => _resolvedBase;

  /// Every base URL worth trying, preferred one first.
  List<String> get _bases {
    final all = <String>[];
    if (_resolvedBase != null) all.add(_resolvedBase!);
    for (final b in [baseUrl, ...mirrorBases]) {
      if (!all.contains(b)) all.add(b);
    }
    return all;
  }

  String get manifestUrl => '$baseUrl/manifest.json';

  String providerUrl(ProviderInfo info) => '$baseUrl/${info.filename}';

  // ── Storage layout ──────────────────────────────────────────────────────
  // <appDocs>/tj_providers/
  //   meta.json          { "cinezo": {version, filePath, downloadedAt, sizeBytes}, ... }
  //   manifest.json      last fetched manifest (for offline use)
  //   cinezo.js          downloaded provider code
  //   screenscape.js
  //   ...

  Future<Directory> _dir() async {
    final dir =
        cacheDir ??
        Directory(
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            'tj_providers',
          ),
        );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _metaFile() async =>
      File(p.join((await _dir()).path, 'meta.json'));
  Future<File> _manifestCacheFile() async =>
      File(p.join((await _dir()).path, 'manifest.json'));

  Future<Map<String, CachedProvider>> getCached() async {
    try {
      final f = await _metaFile();
      if (!await f.exists()) return {};
      final text = await f.readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(
          k,
          CachedProvider.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCached(Map<String, CachedProvider> cached) async {
    final f = await _metaFile();
    final map = cached.map((k, v) => MapEntry(k, v.toJson()));
    await f.writeAsString(jsonEncode(map), flush: true);
  }

  Future<File> providerFile(String id) async {
    final dir = await _dir();
    return File(p.join(dir.path, '$id.js'));
  }

  /// Returns cached JS code for [id], or null if not downloaded yet.
  Future<String?> readProviderCode(String id) async {
    final cached = await getCached();
    final entry = cached[id];
    if (entry == null) return null;
    final f = File(entry.filePath);
    if (!await f.exists()) return null;
    return await f.readAsString();
  }

  /// Last fetched manifest from disk (offline fallback), or null.
  Future<Manifest?> getCachedManifest() async {
    try {
      final f = await _manifestCacheFile();
      if (!await f.exists()) return null;
      return Manifest.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Network ─────────────────────────────────────────────────────────────

  Future<Manifest> fetchManifest() async {
    Object? lastError;
    for (final base in _bases) {
      try {
        final res = await _http
            .get(Uri.parse('$base/manifest.json'))
            .timeout(httpTimeout);
        if (res.statusCode != 200) {
          lastError = Exception('manifest HTTP ${res.statusCode} at $base');
          continue;
        }
        // Decode explicitly as UTF-8 — GitHub raw serves text/plain and some
        // manifests contain non-Latin1 characters (e.g. em dashes).
        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final manifest = Manifest.fromJson(
          jsonDecode(body) as Map<String, dynamic>,
        );
        _resolvedBase = base;
        await cacheManifestJson(body);
        return manifest;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Manifest fetch failed on all mirrors: $lastError');
  }

  /// Store a manifest JSON string as the offline copy (bundled seed or
  /// last-known-good network response).
  Future<void> cacheManifestJson(String json) async {
    try {
      final f = await _manifestCacheFile();
      await f.writeAsString(json, flush: true);
    } catch (_) {}
  }

  Future<String> _downloadProviderCode(ProviderInfo info) async {
    Object? lastError;
    for (final base in _bases) {
      final url = '$base/${info.filename}';
      try {
        final res = await _http.get(Uri.parse(url)).timeout(httpTimeout);
        if (res.statusCode != 200) {
          lastError = Exception('HTTP ${res.statusCode} at $url');
          continue;
        }
        final code = utf8.decode(res.bodyBytes, allowMalformed: true);
        if (code.isEmpty || !code.contains('getStreams')) {
          lastError = Exception('not a provider bundle (missing getStreams)');
          continue;
        }
        _resolvedBase = base;
        return code;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('${info.id}: download failed on all mirrors: $lastError');
  }

  /// Download (or re-download) a single provider and update cache.
  Future<CachedProvider> downloadProvider(ProviderInfo info) async {
    final code = await _downloadProviderCode(info);
    final file = await providerFile(info.id);
    await file.writeAsString(code, flush: true);
    final cached = await getCached();
    final entry = CachedProvider(
      id: info.id,
      version: info.version,
      filePath: file.path,
      downloadedAt: DateTime.now(),
      sizeBytes: code.length,
    );
    cached[info.id] = entry;
    await _saveCached(cached);
    return entry;
  }

  /// Install provider code that ships inside the app (offline seed).
  ///
  /// [read] returns the JS source for an id, or null when the app has no
  /// bundled copy. Existing downloads are kept when they are at least as new as
  /// the bundled version, so a bundled seed never downgrades a live update.
  Future<int> seedBundled({
    required Manifest manifest,
    required Future<String?> Function(String id) read,
    List<String>? onlyIds,
  }) async {
    final cached = await getCached();
    var seeded = 0;
    for (final info in manifest.scrapers) {
      if (onlyIds != null && !onlyIds.contains(info.id)) continue;
      final local = cached[info.id];
      if (local != null && !_isNewer(info.version, local.version)) continue;
      if (local != null) {
        final existing = File(local.filePath);
        if (await existing.exists() && await existing.length() > 0) continue;
      }
      try {
        final code = await read(info.id);
        if (code == null || !code.contains('getStreams')) continue;
        final file = await providerFile(info.id);
        await file.writeAsString(code, flush: true);
        cached[info.id] = CachedProvider(
          id: info.id,
          version: info.version,
          filePath: file.path,
          downloadedAt: DateTime.now(),
          sizeBytes: code.length,
        );
        seeded++;
      } catch (_) {
        // A single bad bundled file must never break startup.
      }
    }
    if (seeded > 0) await _saveCached(cached);
    return seeded;
  }

  /// Download several providers. Returns map id -> error message (empty = success).
  Future<Map<String, String>> downloadProviders(
    List<ProviderInfo> infos,
  ) async {
    final errors = <String, String>{};
    for (final info in infos) {
      try {
        await downloadProvider(info);
      } catch (e) {
        errors[info.id] = e.toString();
      }
    }
    return errors;
  }

  // ── Update check ────────────────────────────────────────────────────────

  /// Compare remote manifest with local cache.
  /// Does NOT download anything — just tells you what changed.
  Future<UpdateCheckResult> checkForUpdates({Manifest? manifest}) async {
    final m = manifest ?? await fetchManifest();
    final cached = await getCached();
    final available = <ProviderInfo>[];
    final updates = <ProviderInfo>[];
    final upToDate = <ProviderInfo>[];

    for (final info in m.scrapers) {
      final local = cached[info.id];
      if (local == null) {
        available.add(info);
      } else if (_isNewer(info.version, local.version)) {
        updates.add(info);
      } else {
        upToDate.add(info);
      }
    }
    final manifestIds = m.scrapers.map((e) => e.id).toSet();
    final removed = cached.keys
        .where((id) => !manifestIds.contains(id))
        .toList();

    return UpdateCheckResult(
      manifest: m,
      available: available,
      updatesAvailable: updates,
      upToDate: upToDate,
      removedIds: removed,
    );
  }

  /// Full sync: fetch manifest, download new + updated providers.
  /// Returns the check result (so UI can show what was updated).
  /// If [onlyIds] is given, only sync those providers (e.g. recommended pack).
  Future<UpdateCheckResult> syncProviders({
    List<String>? onlyIds,
    bool autoUpdate = true,
  }) async {
    final result = await checkForUpdates();
    if (!autoUpdate) return result;

    var toDownload = [...result.available, ...result.updatesAvailable];
    if (onlyIds != null) {
      toDownload = toDownload.where((e) => onlyIds.contains(e.id)).toList();
    }
    if (toDownload.isNotEmpty) {
      await downloadProviders(toDownload);
    }
    // Clean up removed providers
    if (result.removedIds.isNotEmpty) {
      final cached = await getCached();
      for (final id in result.removedIds) {
        try {
          final f = File(cached[id]?.filePath ?? '');
          if (await f.exists()) await f.delete();
        } catch (_) {}
        cached.remove(id);
      }
      await _saveCached(cached);
    }
    return result;
  }

  /// Convenience: sync only the recommended starter pack on first launch.
  Future<UpdateCheckResult> syncRecommended() =>
      syncProviders(onlyIds: recommendedIds);

  /// Remove a cached provider from disk.
  Future<void> removeProvider(String id) async {
    final cached = await getCached();
    final entry = cached.remove(id);
    if (entry != null) {
      try {
        final f = File(entry.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      await _saveCached(cached);
    }
  }

  /// Version comparison: "1.0.12" > "1.0.9" etc.
  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final l = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < len; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  void dispose() => _http.close();
}
