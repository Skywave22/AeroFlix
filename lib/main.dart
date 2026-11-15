import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock app to portrait outside of the player screen (player sets landscape
  // on entry and restores all orientations on dispose).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  MediaKit.ensureInitialized();
  runApp(const AeroFlixApp());
}
