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

  /// Stops and releases the native player.
  ///
  /// Order matters. `player.stop()` makes the decoder release the audio session
  /// and the video surface *before* `dispose()` tears the engine down; disposing
  /// a playing engine directly is what left the previous build's audio running
  /// after the player screen was gone, with the UI blocked behind a wedged
  /// native call. Errors are swallowed on purpose: a disposed engine that
  /// already crashed internally must never take the app down with it.
  Future<void> dispose() async {
    try {
      await player.stop().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await player.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}

final activePlayerProvider =
    StateNotifierProvider.autoDispose<ActivePlayerNotifier, ActivePlayer?>(
        (ref) => ActivePlayerNotifier());

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
    'stream-lavf-o': 'reconnect=1,reconnect_on_network_error=1,'
        'reconnect_streamed=1,reconnect_delay_max=5',
    'audio-stream-silence': 'yes',
  };

  /// [softwareDecode] forces CPU decoding — the fallback when hardware
  /// decoding (MediaCodec) can open a stream but never renders a frame, which
  /// some devices do with certain HLS/mkv links.
  Future<ActivePlayer> play(StreamSource src,
      {bool softwareDecode = false}) async {
    // Detach the old player *before* awaiting its teardown, so two overlapping
    // `play()` calls (a failover landing while the user picked a source from
    // the sheet) cannot both think they own the screen — that used to leave
    // two engines playing the same film a few hundred milliseconds apart.
    final previous = state;
    state = null;
    await previous?.dispose();

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

  bool _disposed = false;

  /// Releases the current player when it is replaced by [play], when the screen
  /// pops (it calls this explicitly so audio stops on the same frame), or when
  /// the provider auto-disposes. Written to be idempotent: both of those paths
  /// can run, and disposing a StateNotifier twice throws.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final current = state;
    state = null;
    super.dispose();
    await current?.dispose();
  }
}
