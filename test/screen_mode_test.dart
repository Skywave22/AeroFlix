import 'package:aeroflix/core/platform/screen_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the "backing out of the player leaves the whole app in
/// landscape" bug.
///
/// V0.2 restored orientation with `setPreferredOrientations(DeviceOrientation
/// .values)` from `_PlayerScreenState.dispose`. That requests *every*
/// orientation — it does not restore the portrait lock from `main()` — so once
/// playback ended the app stayed sideways. The fix moves the decision to the
/// router location; these tests pin the resulting platform calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    ScreenModeController.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  List<MethodCall> callsTo(String method) =>
      calls.where((MethodCall c) => c.method == method).toList();

  /// The system-UI mode requested by the most recent platform call.
  ///
  /// Flutter sends the mode as a bare string (`SystemUiMode.edgeToEdge`) for
  /// every mode except `manual`, which uses a separate overlay-list channel.
  String? lastUiMode() {
    final List<MethodCall> uiCalls =
        callsTo('SystemChrome.setEnabledSystemUIMode');
    if (uiCalls.isEmpty) return null;
    return uiCalls.last.arguments.toString();
  }

  /// The orientation list requested by the most recent platform call.
  List<String>? lastRequestedOrientations() {
    final List<MethodCall> orientationCalls =
        callsTo('SystemChrome.setPreferredOrientations');
    if (orientationCalls.isEmpty) return null;
    return (orientationCalls.last.arguments as List<Object?>)
        .map((Object? e) => e.toString())
        .toList();
  }

  group('modeForLocation', () {
    test('player routes are the only full-screen landscape routes', () {
      expect(
          ScreenModeController.modeForLocation('/player'), ScreenMode.player);
      expect(
          ScreenModeController.modeForLocation('/player/'), ScreenMode.player);
      expect(ScreenModeController.modeForLocation('/details/movie/603'),
          ScreenMode.app);
      expect(ScreenModeController.modeForLocation('/home'), ScreenMode.app);
      expect(ScreenModeController.modeForLocation('/episodes'), ScreenMode.app);
      expect(ScreenModeController.modeForLocation(''), ScreenMode.app);
    });

    test('a path that merely starts with the word player is not the player',
        () {
      expect(ScreenModeController.modeForLocation('/players'), ScreenMode.app);
    });
  });

  group('apply', () {
    test('player mode locks landscape and hides the system bars', () async {
      await ScreenModeController.apply(ScreenMode.player);

      expect(lastRequestedOrientations(), <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      expect(lastUiMode(), 'SystemUiMode.immersiveSticky');
    });

    test('app mode locks portrait only and restores the system bars', () async {
      await ScreenModeController.apply(ScreenMode.app);

      // Exactly one orientation: the old bug was requesting all four.
      expect(lastRequestedOrientations(),
          <String>['DeviceOrientation.portraitUp']);
      expect(lastUiMode(), 'SystemUiMode.edgeToEdge');
      expect(callsTo('SystemChrome.setSystemUIOverlayStyle'), isNotEmpty);
    });

    test('repeating the active mode does not re-issue the platform request',
        () async {
      await ScreenModeController.apply(ScreenMode.app);
      final int afterFirst =
          callsTo('SystemChrome.setPreferredOrientations').length;

      await ScreenModeController.apply(ScreenMode.app);

      expect(
          callsTo('SystemChrome.setPreferredOrientations').length, afterFirst);
    });
  });

  group('backing out of playback', () {
    test('leaving /player returns the app to a portrait-only orientation',
        () async {
      // Enter playback, then pop back to a details screen.
      await ScreenModeController.syncForLocation('/player');
      expect(lastRequestedOrientations(),
          contains('DeviceOrientation.landscapeLeft'));

      await ScreenModeController.syncForLocation('/details/movie/603');

      expect(lastRequestedOrientations(),
          <String>['DeviceOrientation.portraitUp']);
    });

    test('advancing to the next episode keeps landscape', () async {
      // pushReplacement('/player') does not change the location, so the mode
      // must stay put instead of flipping to portrait mid-episode.
      await ScreenModeController.syncForLocation('/player');
      final int before =
          callsTo('SystemChrome.setPreferredOrientations').length;

      await ScreenModeController.syncForLocation('/player');

      expect(callsTo('SystemChrome.setPreferredOrientations').length, before);
      expect(ScreenModeController.current, ScreenMode.player);
    });

    test('reassert re-applies the active mode after a platform config change',
        () async {
      await ScreenModeController.syncForLocation('/player');
      final int before =
          callsTo('SystemChrome.setPreferredOrientations').length;

      await ScreenModeController.reassert();

      expect(
          callsTo('SystemChrome.setPreferredOrientations').length, before + 1);
      expect(lastRequestedOrientations(), <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
    });

    test('reassert before any mode is applied is a no-op', () async {
      await ScreenModeController.reassert();
      expect(calls, isEmpty);
    });
  });
}
