import 'dart:async';
import 'dart:convert';

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

  /// Provider ids to use by default. Defaults to recommended starter pack.
  /// Change to all 25 ids from manifest if you want everything.
  final List<String> enabledIds;

  ProviderService({
    required this.manager,
    this.tmdbApiKey = '',
    this.enabledIds = ProviderManager.recommendedIds,
  });

  /// Call on app start: fetch manifest, download new providers,
  /// auto-update changed ones. Safe to call every launch (fast if up-to-date).
  Future<UpdateCheckResult> syncOnLaunch() async {
    try {
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
    Duration perProviderTimeout = const Duration(seconds: 30),
  }) async* {
    final ids = onlyProviderIds ?? enabledIds;
    for (final id in ids) {
      yield await _runProvider(
        id: id,
        tmdbId: tmdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
        perProviderTimeout: perProviderTimeout,
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
    Duration perProviderTimeout = const Duration(seconds: 30),
  }) async {
    final all = <StreamResult>[];
    await for (final outcome in streamStreams(
      tmdbId: tmdbId,
      mediaType: mediaType,
      season: season,
      episode: episode,
      onlyProviderIds: onlyProviderIds,
      perProviderTimeout: perProviderTimeout,
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
    Duration timeout = const Duration(seconds: 45),
  }) {
    return _runProvider(
      id: id,
      tmdbId: tmdbId,
      mediaType: mediaType,
      season: season,
      episode: episode,
      perProviderTimeout: timeout,
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

  Future<ProviderOutcome> _runProvider({
    required String id,
    required String tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    Duration perProviderTimeout = const Duration(seconds: 30),
  }) async {
    final sw = Stopwatch()..start();
    JsRuntime? runtime;
    try {
      final code = await manager.readProviderCode(id);
      if (code == null) {
        return ProviderOutcome(
          providerId: id,
          error: 'not installed',
          elapsed: sw.elapsed,
        );
      }

      runtime = JsRuntime(tmdbApiKey: tmdbApiKey, scraperId: id);
      final jsonStr = await runtime
          .getStreamsJson(
            providerCode: code,
            providerId: id,
            tmdbId: tmdbId,
            mediaType: mediaType,
            season: season,
            episode: episode,
          )
          .timeout(perProviderTimeout);

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
        error: 'timed out after ${perProviderTimeout.inSeconds}s',
        elapsed: sw.elapsed,
      );
    } catch (e) {
      return ProviderOutcome(
        providerId: id,
        error: e.toString(),
        elapsed: sw.elapsed,
      );
    } finally {
      runtime?.dispose();
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
