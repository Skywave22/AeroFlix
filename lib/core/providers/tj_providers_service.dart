import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

import '../constants/api_constants.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// TJ-Plugins provider wiring.
///
/// Provider JS bundles are downloaded from
/// https://github.com/Skywave22/Plugins-TJ at runtime and cached on the device,
/// so a fix published upstream reaches users on the next launch without an app
/// update. `ProviderService` runs the JS in QuickJS and returns real,
/// playable links for any TMDB id.
/// ─────────────────────────────────────────────────────────────────────────────

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

/// Runs once per app launch: downloads missing providers and picks up
/// upstream version bumps. Errors are swallowed — the app still works with
/// whatever is already cached (see ProviderService.getStreams).
final providerSyncProvider = FutureProvider<UpdateCheckResult?>((ref) async {
  final manager = ref.watch(providerManagerProvider);
  try {
    final result = await manager
        .syncProviders(onlyIds: ProviderManager.recommendedIds)
        .timeout(const Duration(seconds: 90));
    if (kDebugMode) {
      debugPrint('[providers] manifest v${result.manifest.version} · '
          '${result.updatesAvailable.length} updated · '
          '${result.available.length} new');
    }
    return result;
  } catch (e) {
    if (kDebugMode) debugPrint('[providers] sync failed: $e');
    return null;
  }
});

/// Manual "check for updates" used by the Providers screen.
Future<UpdateCheckResult> refreshProviders(WidgetRef ref) async {
  final manager = ref.read(providerManagerProvider);
  final result = await manager.syncProviders(
    onlyIds: ProviderManager.recommendedIds,
  );
  ref.invalidate(installedProvidersProvider);
  ref.invalidate(providerSyncProvider);
  return result;
}
