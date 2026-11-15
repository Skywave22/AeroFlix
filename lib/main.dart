import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'app/app.dart';
import 'core/platform/screen_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock the browsing UI to portrait. From here on the router owns orientation
  // (see ScreenModeController): /player requests landscape, every other route
  // requests portrait, so popping the player always lands back in portrait.
  await ScreenModeController.apply(ScreenMode.app);
  MediaKit.ensureInitialized();
  runApp(const AeroFlixApp());
}
