import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../shared/models/media_details.dart';

/// Full-screen immersive video player.
///
/// Phase 1: UI shell with play/pause, seek, quality, subtitles, lock.
/// Real playback via media_kit wires in when the stream provider
/// returns working URLs.
class PlayerScreen extends StatefulWidget {
  final MediaDetails details;
  final int season;
  final int episode;
  final String? episodeTitle;

  const PlayerScreen({
    super.key,
    required this.details,
    this.season = 0,
    this.episode = 0,
    this.episodeTitle,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showControls = true;
  bool _playing = false;
  bool _loading = true;
  bool _locked = false;
  double _position = 0;
  double _duration = 1; // replaced with real duration when media_kit is wired

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Phase 2: media_kit controller initialization starts here.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _togglePlay() => setState(() => _playing = !_playing);
  void _toggleControls() => setState(() => _showControls = !_showControls);

  String _label() {
    if (widget.details.type == MediaType.tv && widget.season > 0) {
      final ep = widget.episodeTitle ?? 'Episode ${widget.episode}';
      return '${widget.details.title}  ·  S${widget.season.toString().padLeft(2, '0')}E${widget.episode.toString().padLeft(2, '0')}  ·  $ep';
    }
    return widget.details.title;
  }

  String _fmt(double s) {
    final d = Duration(seconds: s.toInt());
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(fit: StackFit.expand, children: [
          // Placeholder video surface — replaced by Video() controller in Phase 2.
          Container(color: Colors.black),
          if (widget.details.backdropUrlW1280.isNotEmpty)
            Positioned.fill(
                child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.5), BlendMode.dstOver),
              child: Image.network(widget.details.backdropUrlW1280,
                  fit: BoxFit.cover),
            )),

          // Center play/loading indicator
          Center(
              child: _loading
                  ? const CircularProgressIndicator(
                      color: AppColors.accent, strokeWidth: 2)
                  : IconButton(
                      icon: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 64,
                          color: AppColors.textPrimary
                              .withValues(alpha: _showControls ? 1 : 0)),
                      onPressed: _showControls ? _togglePlay : null)),

          // Top bar
          AnimatedOpacity(
              opacity: _showControls && !_locked ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [AppColors.overlay70, Colors.transparent])),
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
                    child: SafeArea(
                        bottom: false,
                        child: Row(children: [
                          IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                  size: 20, color: AppColors.textPrimary),
                              onPressed: () => Navigator.of(context).pop(),
                              splashRadius: 20),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(_label(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyPrimary
                                      .copyWith(fontSize: 13))),
                          IconButton(
                              icon: Icon(
                                  _locked
                                      ? Icons.lock_outline
                                      : Icons.lock_open_rounded,
                                  size: 20,
                                  color: AppColors.textPrimary),
                              onPressed: () =>
                                  setState(() => _locked = !_locked),
                              splashRadius: 20),
                        ])),
                  ))),

          // Bottom controls
          AnimatedOpacity(
              opacity: _showControls && !_locked ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, AppColors.overlay70])),
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: SafeArea(
                        top: false,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          // Seek bar
                          SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12),
                                activeTrackColor: AppColors.accent,
                                inactiveTrackColor: AppColors.surfaceElevated,
                                thumbColor: AppColors.accent,
                              ),
                              child: Slider(
                                  value: _position /
                                      (_duration == 0 ? 1 : _duration)
                                          .clamp(0, 1),
                                  onChanged: (v) => setState(
                                      () => _position = v * _duration))),
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(children: [
                                Text(_fmt(_position),
                                    style: AppTypography.metadata.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 11)),
                                const Spacer(),
                                Text(_fmt(_duration),
                                    style: AppTypography.metadata.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 11)),
                              ])),
                          const SizedBox(height: 4),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                    icon: const Icon(Icons.replay_10_rounded,
                                        color: AppColors.textPrimary, size: 28),
                                    onPressed: () {}),
                                IconButton(
                                    icon: const Icon(
                                        Icons.skip_previous_rounded,
                                        color: AppColors.textPrimary,
                                        size: 28),
                                    onPressed: () {}),
                                IconButton(
                                    icon: Icon(
                                        _playing
                                            ? Icons.pause_circle_filled_rounded
                                            : Icons.play_circle_fill_rounded,
                                        color: AppColors.textPrimary,
                                        size: 48),
                                    onPressed: _togglePlay),
                                IconButton(
                                    icon: const Icon(Icons.skip_next_rounded,
                                        color: AppColors.textPrimary, size: 28),
                                    onPressed: () {}),
                                IconButton(
                                    icon: const Icon(Icons.forward_10_rounded,
                                        color: AppColors.textPrimary, size: 28),
                                    onPressed: () {}),
                                const Spacer(),
                                IconButton(
                                    icon: const Icon(
                                        Icons.closed_caption_off_rounded,
                                        color: AppColors.textPrimary,
                                        size: 22),
                                    onPressed: () {}),
                                IconButton(
                                    icon: const Icon(Icons.hd_outlined,
                                        color: AppColors.textPrimary, size: 22),
                                    onPressed: () {}),
                                IconButton(
                                    icon: const Icon(Icons.speed_rounded,
                                        color: AppColors.textPrimary, size: 22),
                                    onPressed: () {}),
                                IconButton(
                                    icon: const Icon(Icons.fit_screen_rounded,
                                        color: AppColors.textPrimary, size: 22),
                                    onPressed: () {}),
                              ]),
                        ])),
                  ))),
        ]),
      ),
    );
  }
}
