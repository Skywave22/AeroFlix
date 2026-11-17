import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/navigation/deep_link_handler.dart';
import '../core/platform/screen_mode.dart';
import '../core/providers/tj_providers_service.dart';
import 'theme/app_theme.dart';
import 'router.dart';

class AeroFlixApp extends StatefulWidget {
  const AeroFlixApp({super.key});
  @override
  State<AeroFlixApp> createState() => _AeroFlixAppState();
}

class _AeroFlixAppState extends State<AeroFlixApp> {
  /// Tracks the widget so lifecycle callbacks can be released with it.
  late final VoidCallback _screenModeListener;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(appSystemOverlayStyle);
    // The router — not the individual screens — owns orientation. Every
    // navigation (push, pop, back gesture, deep link, episode auto-advance)
    // re-applies the mode for the location that was landed on, so the app can
    // never be stranded in landscape after playback.
    _screenModeListener = _syncScreenMode;
    appRouter.routerDelegate.addListener(_screenModeListener);
    _syncScreenMode();
  }

  @override
  void dispose() {
    appRouter.routerDelegate.removeListener(_screenModeListener);
    super.dispose();
  }

  /// Applies the screen mode implied by the router's current location.
  void _syncScreenMode() {
    final path = appRouter.routerDelegate.currentConfiguration.uri.path;
    unawaited(ScreenModeController.syncForLocation(path));
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
        // Kicks off the provider download/update pass at startup; the app is
        // usable immediately with whatever is already cached.
        child: _ProviderBootstrap(
            child: DeepLinkHandler(
                router: appRouter,
                child: MaterialApp.router(
                    title: 'AeroFlix',
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.dark(),
                    // Never let an extreme system font scale make the UI unreadable
                    // (0.9x) or break layouts (1.35x). The base type scale is already
                    // larger than Material defaults after the legibility pass.
                    builder: (context, child) {
                      final mq = MediaQuery.of(context);
                      return MediaQuery(
                        data: mq.copyWith(
                          textScaler: mq.textScaler.clamp(
                            minScaleFactor: 0.9,
                            maxScaleFactor: 1.35,
                          ),
                        ),
                        child: child ?? const SizedBox.shrink(),
                      );
                    },
                    routerConfig: appRouter))));
  }
}

/// Starts the one-shot TJ provider sync and keeps the result (and any
/// providers already on disk) available to the widget tree.
class _ProviderBootstrap extends ConsumerWidget {
  const _ProviderBootstrap({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(providerSyncProvider);
    ref.watch(installedProvidersProvider);
    return child;
  }
}
