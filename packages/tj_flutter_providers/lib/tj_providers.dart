/// TJ Flutter Providers — run Plugins-TJ Nuvio providers in Flutter.
///
/// Quick start:
/// ```dart
/// import 'package:tj_flutter_providers/tj_providers.dart';
///
/// final manager = ProviderManager();
/// final service = ProviderService(manager: manager, tmdbApiKey: 'YOUR_TMDB_KEY');
/// await service.syncOnLaunch(); // downloads + auto-updates providers from GitHub
/// final streams = await service.getStreams(tmdbId: '27205', mediaType: 'movie');
/// ```
library;

export 'src/models.dart';
export 'src/provider_manager.dart';
export 'src/provider_service.dart';
export 'src/js_runtime.dart';
export 'src/crypto_bridge.dart';
export 'src/widgets/providers_screen.dart';
export 'src/widgets/streams_sheet.dart';
