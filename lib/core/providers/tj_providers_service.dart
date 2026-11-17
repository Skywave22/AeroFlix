import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

import '../constants/api_constants.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// TJ-Plugins provider wiring.
///
/// Providers resolve into two layers:
///
/// 1. **Bundled seed** (`assets/providers/`) — a snapshot of
///    https://github.com/Skywave22/Plugins-TJ that ships with the APK. First
///    launch works with no network and on carriers where GitHub is blocked.
/// 2. **Auto-update** — the manifest is fetched from GitHub (raw, then jsDelivr,
///    then githack) and any provider whose version moved is re-downloaded. A
///    fix published upstream therefore reaches users on the next launch without
///    an app update.
///
/// Everything the sync does is reported in [ProviderStatus] so the in-app
/// diagnostics screen can show exactly what happened on a device.
/// ─────────────────────────────────────────────────────────────────────────────

const String kBundledProvidersDir = 'assets/providers';
const String kBundledManifestPath = '$kBundledProvidersDir/manifest.json';

final providerManagerProvider = Provider<ProviderManager>((ref) {
  final manager = ProviderManager();
  ref.onDispose(manager.dispose);
  return manager;
});

final providerServiceProvider = Provider<ProviderService>((ref) {
  return ProviderService(
    manager: ref.watch(providerManagerProvider),
    tmdbApiKey: ApiConstants.tmdbApiKey,
    enabledIds: ProviderManager.recommendedIds,
  );
});

/// Providers currently cached on disk (id -> cached info).
final installedProvidersProvider =
    FutureProvider<Map<String, CachedProvider>>((ref) {
  return ref.watch(providerManagerProvider).getCached();
});

enum ProviderPhase { idle, seeding, syncing, ready }

@immutable
class ProviderStatus {
  const ProviderStatus({
    this.phase = ProviderPhase.idle,
    this.seeded = 0,
    this.installed = 0,
    this.updated = 0,
    this.mirror,
    this.error,
    this.syncedAt,
  });

  final ProviderPhase phase;

  /// Providers copied out of the APK assets on this launch.
  final int seeded;

  /// Providers present on disk after seeding.
  final int installed;

  /// Providers re-downloaded because upstream had a newer version.
  final int updated;

  /// Mirror that answered, e.g. `cdn.jsdelivr.net`.
  final String? mirror;

  /// Why the network half failed (seed still leaves the app working).
  final String? error;

  final DateTime? syncedAt;

  bool get busy =>
      phase == ProviderPhase.seeding || phase == ProviderPhase.syncing;

  String get summary {
    switch (phase) {
      case ProviderPhase.idle:
        return 'Not started';
      case ProviderPhase.seeding:
        return 'Installing bundled providers…';
      case ProviderPhase.syncing:
        return 'Checking GitHub for provider updates…';
      case ProviderPhase.ready:
        if (error != null) {
          return '$installed providers ready (offline — ${_short(error!)})';
        }
        return '$installed providers ready${updated > 0 ? ' · $updated updated' : ''}';
    }
  }

  static String _short(String e) =>
      e.length <= 120 ? e : '${e.substring(0, 120)}…';

  ProviderStatus copyWith({
    ProviderPhase? phase,
    int? seeded,
    int? installed,
    int? updated,
    String? mirror,
    String? error,
    DateTime? syncedAt,
    bool clearError = false,
  }) {
    return ProviderStatus(
      phase: phase ?? this.phase,
      seeded: seeded ?? this.seeded,
      installed: installed ?? this.installed,
      updated: updated ?? this.updated,
      mirror: mirror ?? this.mirror,
      error: clearError ? null : (error ?? this.error),
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}

/// Seeds bundled providers, then syncs with GitHub — once per app launch.
class ProviderStatusNotifier extends Notifier<ProviderStatus> {
  Future<void>? _running;

  @override
  ProviderStatus build() => const ProviderStatus();

  Future<void> bootstrap() => _running ??= _run();

  /// Manual "check again" from the diagnostics screen.
  Future<void> refresh() {
    _running = null;
    return _running = _run();
  }

  Future<void> _run() async {
    final manager = ref.read(providerManagerProvider);
    var seeded = 0;

    // 1. Bundled seed — never fails, never needs the network.
    state = state.copyWith(phase: ProviderPhase.seeding, clearError: true);
    try {
      final raw = await rootBundle.loadString(kBundledManifestPath);
      await manager.cacheManifestJson(raw);
      final manifest = Manifest.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      seeded = await manager.seedBundled(
        manifest: manifest,
        read: (id) async {
          try {
            return await rootBundle.loadString('$kBundledProvidersDir/$id.js');
          } catch (_) {
            return null;
          }
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[providers] bundled seed failed: $e');
    }

    var installed = (await manager.getCached()).keys.length;
    state = state.copyWith(
      phase: ProviderPhase.syncing,
      seeded: seeded,
      installed: installed,
    );

    // 2. Upstream sync — best effort, the app already works from the seed.
    var updated = 0;
    String? error;
    try {
      final before = await manager.getCached();
      final result = await manager
          .syncProviders(onlyIds: ProviderManager.recommendedIds)
          .timeout(const Duration(seconds: 60));
      final after = await manager.getCached();
      updated = after.entries
          .where((e) =>
              before[e.key]?.version != e.value.version ||
              before[e.key]?.sizeBytes != e.value.sizeBytes)
          .length;
      installed = after.keys.length;
      if (kDebugMode) {
        debugPrint('[providers] manifest v${result.manifest.version} · '
            'seeded $seeded · updated $updated · installed $installed');
      }
    } catch (e) {
      error = e.toString();
      if (kDebugMode) debugPrint('[providers] sync failed: $e');
    }

    state = ProviderStatus(
      phase: ProviderPhase.ready,
      seeded: seeded,
      installed: installed,
      updated: updated,
      mirror: manager.resolvedBaseUrl,
      error: error,
      syncedAt: DateTime.now(),
    );
    ref.invalidate(installedProvidersProvider);
  }
}

final providerStatusProvider =
    NotifierProvider<ProviderStatusNotifier, ProviderStatus>(
  ProviderStatusNotifier.new,
);

/// Manual "check for updates" used by the Providers screen.
Future<UpdateCheckResult> refreshProviders(WidgetRef ref) async {
  final manager = ref.read(providerManagerProvider);
  final result = await manager.syncProviders(
    onlyIds: ProviderManager.recommendedIds,
  );
  ref.invalidate(installedProvidersProvider);
  await ref.read(providerStatusProvider.notifier).refresh();
  return result;
}
