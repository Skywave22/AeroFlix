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

  /// Get streams for a title from all enabled + downloaded providers.
  /// Providers run in parallel; failures return [] for that provider
  /// (getStreams never throws in the JS adapter — it returns [] on error).
  Future<List<StreamResult>> getStreams({
    required String tmdbId,
    required String mediaType, // "movie" | "tv"
    int? season,
    int? episode,
    List<String>? onlyProviderIds,
  }) async {
    final ids = onlyProviderIds ?? enabledIds;
    final futures = <Future<List<StreamResult>>>[];

    for (final id in ids) {
      futures.add(
        _getStreamsForProvider(
          id: id,
          tmdbId: tmdbId,
          mediaType: mediaType,
          season: season,
          episode: episode,
        ),
      );
    }

    final results = await Future.wait(futures);
    final all = results.expand((e) => e).toList();

    // Sort: Hindi first, then best quality (4K > 1080p > 720p...), matching Nuvio behavior
    all.sort((a, b) {
      final aHindi = _isHindi(a) ? 0 : 1;
      final bHindi = _isHindi(b) ? 0 : 1;
      if (aHindi != bHindi) return aHindi.compareTo(bHindi);
      return _qualityRank(b.quality).compareTo(_qualityRank(a.quality));
    });
    return all;
  }

  Future<List<StreamResult>> _getStreamsForProvider({
    required String id,
    required String tmdbId,
    required String mediaType,
    int? season,
    int? episode,
  }) async {
    try {
      final code = await manager.readProviderCode(id);
      if (code == null)
        return []; // not downloaded yet — call syncOnLaunch() first

      final runtime = JsRuntime(tmdbApiKey: tmdbApiKey, scraperId: id);
      try {
        final jsonStr = await runtime
            .getStreamsJson(
              providerCode: code,
              providerId: id,
              tmdbId: tmdbId,
              mediaType: mediaType,
              season: season,
              episode: episode,
            )
            .timeout(const Duration(seconds: 60)); // Nuvio 60s provider limit

        final decoded = jsonDecode(jsonStr);
        if (decoded is! List) return [];
        return decoded
            .whereType<Map>()
            .map((e) => StreamResult.fromJson(Map<String, dynamic>.from(e)))
            .where((s) => s.url.isNotEmpty)
            .toList();
      } finally {
        runtime.dispose();
      }
    } catch (_) {
      return []; // provider failed — other providers still return results
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
