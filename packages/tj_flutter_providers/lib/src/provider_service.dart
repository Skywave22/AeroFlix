import 'dart:async';
import 'dart:convert';

import 'isolate_runner.dart';
import 'js_runtime.dart';
import 'models.dart';
import 'provider_manager.dart';

/// High-level API your app calls: TMDB id in, playable streams out.
///
/// ```dart
/// final manager = ProviderManager();
/// final service = ProviderService(manager: manager, tmdbApiKey: 'YOUR_KEY');
///
/// // On app start: download recommended providers + check for updates
/// await service.syncOnLaunch();
///
/// // On movie page: get streams from all enabled providers in parallel
/// final streams = await service.getStreams(
///   tmdbId: '27205', mediaType: 'movie',
/// );
/// // streams: [StreamResult(name: "Cinezo · Nitro", url: "https://...m3u8", ...), ...]
/// ```
class ProviderService {
  final ProviderManager manager;
  final String tmdbApiKey;

  /// Provider ids currently active. Defaults to the recommended starter pack.
  ///
  /// Mutable through [setEnabledIds] because the Providers screen can switch
  /// providers at runtime; previously this was a plain `final` list, so every
  /// toggle in that screen was silently discarded and all calls kept using the
  /// constructor value.
  List<String> _enabledIds;
  List<String> get enabledIds => _enabledIds;

  /// Replace the active provider set (takes effect on the next call).
  void setEnabledIds(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isNotEmpty) _enabledIds = List.unmodifiable(list);
  }

  /// Per-provider settings exposed to the JS bundle as `globalThis.SCRAPER_SETTINGS`
  /// and via `getPreference(key)`. The all-in-one provider needs its unlock code
  /// here (`tj_aio_code`) or it returns nothing.
  final Map<String, dynamic> scraperSettings;

  /// Run providers on a background isolate (recommended: keeps the UI at
  /// 60 fps). Falls back to in-process execution automatically when a platform
  /// cannot host one.
  final bool useIsolate;

  /// Default per-provider time budget. The TJ All-in-one bundle fans out to
  /// every site at once and legitimately needs 40-60 s on a cold run, so the
  /// default is generous; callers can still pass a tighter value per call.
  final Duration timeout;

  bool _isolateBroken = false;

  ProviderService({
    required this.manager,
    this.tmdbApiKey = '',
    List<String>? enabledIds,
    this.useIsolate = true,
    this.scraperSettings = const {},
    this.timeout = const Duration(seconds: 105),
  }) : _enabledIds = List.unmodifiable(
         enabledIds ?? ProviderManager.recommendedIds,
       );

  /// Call on app start: fetch manifest, download new providers,
  /// auto-update changed ones. Safe to call every launch (fast if up-to-date).
  Future<UpdateCheckResult> syncOnLaunch() async {
    try {
      // Drop bundles from other provider layouts before syncing.
      await manager.pruneTo(enabledIds);
      return await manager.syncProviders(onlyIds: enabledIds);
    } catch (_) {
      // Offline / GitHub down: fall back to cached manifest + cached providers.
      // getStreams() will still work with whatever is already downloaded.
      final cachedManifest = await manager.getCachedManifest();
      if (cachedManifest != null) {
        final cached = await manager.getCached();
        return UpdateCheckResult(
          manifest: cachedManifest,
          available: cachedManifest.scrapers
              .where((p) => !cached.containsKey(p.id))
              .toList(),
          updatesAvailable: const [],
          upToDate: cachedManifest.scrapers
              .where((p) => cached.containsKey(p.id))
              .toList(),
        );
      }
      rethrow;
    }
  }

  /// Manual refresh from UI (pull-to-refresh / "Check for updates" button).
  Future<UpdateCheckResult> checkAndUpdate() =>
      manager.syncProviders(onlyIds: enabledIds);

  /// Run every enabled provider for a title, yielding one [ProviderOutcome] per
  /// provider as soon as it finishes.
  ///
  /// QuickJS execution is synchronous, so providers run one after another —
  /// this API exists so the UI can start playback on the first hit instead of
  /// waiting for the slowest one.
  Stream<ProviderOutcome> streamStreams({
    required String tmdbId,
    required String mediaType, // "movie" | "tv"
    int? season,
    int? episode,
    List<String>? onlyProviderIds,
    Duration? perProviderTimeout,
  }) async* {
    final ids = onlyProviderIds ?? enabledIds;
    for (final id in ids) {
      yield await _runProvider(
        id: id,
        tmdbId: tmdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
        perProviderTimeout: perProviderTimeout ?? timeout,
      );
    }
  }

  /// Get streams for a title from all enabled + downloaded providers.
  /// Providers run one after another inside QuickJS; failures return [] for that
  /// provider (getStreams never throws in the JS adapter).
  Future<List<StreamResult>> getStreams({
    required String tmdbId,
    required String mediaType, // "movie" | "tv"
    int? season,
    int? episode,
    List<String>? onlyProviderIds,
    Duration? perProviderTimeout,
  }) async {
    final all = <StreamResult>[];
    await for (final outcome in streamStreams(
      tmdbId: tmdbId,
      mediaType: mediaType,
      season: season,
      episode: episode,
      onlyProviderIds: onlyProviderIds,
      perProviderTimeout: perProviderTimeout ?? timeout,
    )) {
      all.addAll(outcome.streams);
    }

    // Sort: Hindi first, then best quality (4K > 1080p > 720p...), matching Nuvio behavior
    all.sort((a, b) {
      final aHindi = _isHindi(a) ? 0 : 1;
      final bHindi = _isHindi(b) ? 0 : 1;
      if (aHindi != bHindi) return aHindi.compareTo(bHindi);
      return _qualityRank(b.quality).compareTo(_qualityRank(a.quality));
    });
    return all;
  }

  /// Run a single provider — used by the in-app diagnostics screen.
  ///
  /// Defaults to a title every provider carries (TMDB 550, Fight Club).
  Future<ProviderOutcome> testProvider(
    String id, {
    String tmdbId = '550',
    String mediaType = 'movie',
    int? season,
    int? episode,
    Duration? timeout,
  }) {
    return _runProvider(
      id: id,
      tmdbId: tmdbId,
      mediaType: mediaType,
      season: season,
      episode: episode,
      perProviderTimeout: timeout ?? this.timeout,
    );
  }

  /// Provider ids that have code cached on the device.
  Future<List<String>> installedProviderIds() async {
    final cached = await manager.getCached();
    final ids = <String>[];
    for (final entry in cached.entries) {
      final code = await manager.readProviderCode(entry.key);
      if (code != null && code.isNotEmpty) ids.add(entry.key);
    }
    return ids;
  }

  /// Runs the provider either off-isolate or in-process.
  Future<String> _execute({
    required String providerCode,
    required String providerId,
    required String tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    required Duration timeout,
  }) async {
    if (useIsolate && !_isolateBroken) {
      try {
        final assets = await TjRuntimeAssets.load();
        return await IsolateProviderRunner.run(
          providerCode: providerCode,
          providerId: providerId,
          tmdbApiKey: tmdbApiKey,
          tmdbId: tmdbId,
          mediaType: mediaType,
          season: season,
          episode: episode,
          polyfillCode: assets.polyfill,
          callCode: assets.call,
          cryptoJsCode: assets.cryptoJs,
          settings: {
            for (final e in scraperSettings.entries) e.key: '${e.value}',
          },
          timeout: timeout,
        );
      } on IsolateUnavailable {
        _isolateBroken = true; // platform cannot host one; stop trying
      } on TimeoutException {
        rethrow; // genuine provider timeout — don't retry in-process
      } catch (_) {
        // First run failed (e.g. debug-mode messenger restriction): fall back
        // for this call and keep using the isolate next time.
      }
    }
    final runtime = JsRuntime(
      tmdbApiKey: tmdbApiKey,
      scraperId: providerId,
      scraperSettings: scraperSettings,
    );
    try {
      return await runtime
          .getStreamsJson(
            providerCode: providerCode,
            providerId: providerId,
            tmdbId: tmdbId,
            mediaType: mediaType,
            season: season,
            episode: episode,
          )
          .timeout(timeout);
    } finally {
      runtime.dispose();
    }
  }

  Future<ProviderOutcome> _runProvider({
    required String id,
    required String tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    Duration? perProviderTimeout,
  }) async {
    final budget = perProviderTimeout ?? timeout;
    final sw = Stopwatch()..start();
    try {
      final code = await manager.readProviderCode(id);
      if (code == null) {
        return ProviderOutcome(
          providerId: id,
          error: 'not installed',
          elapsed: sw.elapsed,
        );
      }

      final jsonStr = await _execute(
        providerCode: code,
        providerId: id,
        tmdbId: tmdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
        timeout: budget,
      );

      final decoded = jsonDecode(jsonStr);
      final streams = decoded is List
          ? decoded
                .whereType<Map>()
                .map((e) => StreamResult.fromJson(Map<String, dynamic>.from(e)))
                .where((s) => s.url.isNotEmpty)
                .toList()
          : <StreamResult>[];
      return ProviderOutcome(
        providerId: id,
        streams: streams,
        elapsed: sw.elapsed,
      );
    } on TimeoutException {
      return ProviderOutcome(
        providerId: id,
        error: 'timed out after ${budget.inSeconds}s',
        elapsed: sw.elapsed,
      );
    } catch (e) {
      return ProviderOutcome(
        providerId: id,
        error: e.toString(),
        elapsed: sw.elapsed,
      );
    }
  }

  static bool _isHindi(StreamResult s) {
    final text = '${s.language ?? ''} ${s.name} ${s.title}'.toLowerCase();
    return text.contains('hindi') ||
        text.contains('हिंदी') ||
        text.contains('हिन्दी');
  }

  static int _qualityRank(String q) {
    final s = q.toLowerCase();
    if (s.contains('4k') || s.contains('2160')) return 5;
    if (s.contains('1440')) return 4;
    if (s.contains('1080')) return 3;
    if (s.contains('720')) return 2;
    if (s.contains('480')) return 1;
    return 0;
  }
}
