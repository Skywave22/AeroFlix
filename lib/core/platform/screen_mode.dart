import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';

/// The status / navigation bar styling used by every non-player route.
///
/// Kept here (rather than in `app.dart`) so that whichever code restores the
/// app mode also restores the matching bar colours — the player hides them
/// entirely, and a restore that forgets them leaves a transparent status bar
/// with dark icons over the dark theme.
const SystemUiOverlayStyle appSystemOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: AppColors.background,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// Full-screen modes the app can be in.
enum ScreenMode {
  /// Normal browsing UI: portrait only, system bars visible.
  app,

  /// Playback UI: landscape only, system bars hidden (immersive).
  player,
}

/// Single source of truth for the app's orientation and system UI mode.
///
/// ## Why this exists
///
/// V0.2 set the orientation imperatively from `_PlayerScreenState`:
/// `initState` locked landscape, `dispose` called
/// `setPreferredOrientations(DeviceOrientation.values)`. That last line does
/// not restore the app's portrait lock — it *unlocks every orientation*, so the
/// moment playback ends the whole app is free to stay in whatever orientation
/// the device is physically in (landscape, because that is how people hold a
/// phone while watching). The result: back out of the player and the home /
/// details screens stay sideways until the device itself is rotated.
///
/// It was also racy. A route is disposed *after* its replacement has been built,
/// so `context.pushReplacement('/player')` (auto-advance to the next episode)
/// ran the new player's landscape lock first and the old player's unlock ~300 ms
/// later — mid-episode, with the player still on screen.
///
/// Driving the mode from the router's current location instead means the mode
/// is a pure function of *where you are*, not of which widget happened to be
/// created or destroyed first. Pop, back gesture, deep link, episode
/// auto-advance and cold start all resolve to exactly one orientation.
class ScreenModeController {
  ScreenModeController._();

  /// Portrait lock for the browsing UI — mirrors `main()`.
  static const List<DeviceOrientation> _appOrientations = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  /// Landscape lock for playback. `portraitDown` is deliberately excluded: many
  /// devices report it as unsupported and re-introducing it here would let the
  /// player land upside down.
  static const List<DeviceOrientation> _playerOrientations =
      <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ];

  static ScreenMode? _current;

  /// The mode currently applied, or `null` before the first call.
  static ScreenMode? get current => _current;

  /// Applies [mode], skipping the platform round-trip when it is already active.
  ///
  /// Idempotence matters: the router notifies on every configuration change
  /// (including same-path rebuilds) and re-issuing the request would replay the
  /// platform rotation animation.
  static Future<void> apply(ScreenMode mode) async {
    if (_current == mode) return;
    _current = mode;
    switch (mode) {
      case ScreenMode.player:
        await SystemChrome.setPreferredOrientations(_playerOrientations);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      case ScreenMode.app:
        // Order matters on Android: leave immersive mode first, restore the bar
        // styling second, and request the orientation last so the rotation is
        // applied to a window whose insets are already back.
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(appSystemOverlayStyle);
        await SystemChrome.setPreferredOrientations(_appOrientations);
    }
  }

  /// Re-applies the active mode, bypassing the idempotence check.
  ///
  /// Android drops the requested orientation when the activity is recreated
  /// (task switch, PiP enter/exit, process restore), so those transitions ask
  /// for the mode again even though it has not changed logically.
  static Future<void> reassert() async {
    final mode = _current;
    if (mode == null) return;
    _current = null;
    await apply(mode);
  }

  /// Picks the mode for a router location path.
  static ScreenMode modeForLocation(String path) =>
      path == '/player' || path.startsWith('/player/')
      ? ScreenMode.player
      : ScreenMode.app;

  /// Applies the mode implied by a router location path.
  static Future<void> syncForLocation(String path) =>
      apply(modeForLocation(path));

  /// Restores the pre-test state. Test-only.
  @visibleForTesting
  static void resetForTesting() => _current = null;
}
