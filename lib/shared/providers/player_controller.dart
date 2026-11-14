import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../shared/models/stream_source.dart';

/// Holds an active media_kit Player + VideoController bound to a selected
/// StreamSource. Disposed when the player screen is popped.
class ActivePlayer {
  final Player player;
  final VideoController controller;
  final StreamSource source;
  ActivePlayer(this.player, this.controller, this.source);

  Future<void> dispose() async {
    await player.stop();
    await player.dispose();
  }
}

final activePlayerProvider =
    StateNotifierProvider.autoDispose<ActivePlayerNotifier, ActivePlayer?>(
        (ref) => ActivePlayerNotifier());

class ActivePlayerNotifier extends StateNotifier<ActivePlayer?> {
  ActivePlayerNotifier() : super(null);

  Future<ActivePlayer> play(StreamSource src) async {
    await state?.dispose();
    final player = Player();
    final vc = VideoController(player);
    state = ActivePlayer(player, vc, src);
    await player.open(Media(src.url, httpHeaders: src.headers), play: true);
    return state!;
  }

  @override
  Future<void> dispose() async {
    await state?.dispose();
    super.dispose();
  }
}
