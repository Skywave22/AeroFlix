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
      (ref) => ActivePlayerNotifier(),
    );

class ActivePlayerNotifier extends StateNotifier<ActivePlayer?> {
  ActivePlayerNotifier() : super(null);

  /// mpv/ffmpeg options tuned for the flaky one-off CDNs the providers return.
  ///
  /// Defaults are sized for local files: with them, a 900 kb/s HLS stream plays
  /// for a second, starves, and loops in "buffering" forever. A real cache plus
  /// reconnect support is what makes these links watchable.
  static const Map<String, String> _baseOptions = {
    'cache': 'yes',
    'cache-secs': '30',
    'cache-pause-initial': 'yes',
    'demuxer-max-bytes': '96MiB',
    'demuxer-max-back-bytes': '32MiB',
    'demuxer-readahead-secs': '30',
    'network-timeout': '30',
    'stream-lavf-o':
        'reconnect=1,reconnect_on_network_error=1,'
        'reconnect_streamed=1,reconnect_delay_max=5',
    'audio-stream-silence': 'yes',
  };

  /// [softwareDecode] forces CPU decoding — the fallback when hardware
  /// decoding (MediaCodec) can open a stream but never renders a frame, which
  /// some devices do with certain HLS/mkv links.
  Future<ActivePlayer> play(
    StreamSource src, {
    bool softwareDecode = false,
  }) async {
    await state?.dispose();

    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'AeroFlix',
        // 64 MiB read-ahead; the default is far too small for 1080p HLS.
        bufferSize: 64 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    final vc = VideoController(player);
    state = ActivePlayer(player, vc, src);

    // `setProperty` lives on the native platform implementation (libmpv
    // options have no cross-platform API in media_kit), hence the dynamic call.
    final dynamic native = player.platform;
    final options = <String, String>{
      ..._baseOptions,
      'hwdec': softwareDecode ? 'no' : 'auto-safe',
    };
    for (final entry in options.entries) {
      try {
        await native?.setProperty(entry.key, entry.value);
      } catch (_) {
        // Older libmpv builds may not know every option — never fail on this.
      }
    }

    await player.open(Media(src.url, httpHeaders: src.headers), play: true);
    return state!;
  }

  @override
  Future<void> dispose() async {
    await state?.dispose();
    super.dispose();
  }
}
