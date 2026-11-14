import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';
import '../../shared/providers/stream_providers.dart';

/// Full-screen immersive video player.
///
/// Phase 1 progress:
///   • Fetches real stream URLs from registered providers (Cinezo live).
///   • Shows a source selector if multiple streams are found; auto-picks
///     the highest-quality source otherwise.
///   • Renders full landscape UI with play/pause/seek/±10s/skip/CC/
///     quality/speed/fullscreen/lock controls, auto-hiding overlay.
///   • Phase 2: replace backdrop scrim with media_kit Video controller
///     and bind real playback state (position/duration/buffering).
class PlayerScreen extends ConsumerStatefulWidget {
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
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showControls = true;
  bool _playing = false;
  bool _locked = false;
  double _position = 0;
  final double _duration = 1;

  List<StreamSource> _sources = const [];
  StreamSource? _selected;
  bool _loadingSources = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() {
      _loadingSources = true;
      _error = null;
    });
    try {
      final svc = ref.read(streamServiceProvider);
      final list = await svc.getAllStreams(widget.details,
          season: widget.season, episode: widget.episode);
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _loadingSources = false;
          _error = 'No streams found from any provider.';
        });
        return;
      }
      list.sort((a, b) => _qRank(b.quality).compareTo(_qRank(a.quality)));
      setState(() {
        _sources = list;
        _selected = list.first;
        _loadingSources = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSources = false;
        _error = 'Failed to load streams: $e';
      });
    }
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

  int _qRank(String? q) => switch (q) {
        '4K' => 5,
        '1080p' => 4,
        '720p' => 3,
        null => 3,
        '480p' => 2,
        '360p' => 1,
        _ => 0
      };

  void _openSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Padding(
                padding: const EdgeInsets.only(
                    left: 20, top: 16, right: 20, bottom: 8),
                child:
                    Text('Select Source', style: AppTypography.sectionHeading)),
            if (_selected != null)
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Now playing: ${_selected!.name}',
                      style: AppTypography.metadata
                          .copyWith(color: AppColors.textMuted))),
            Flexible(
                child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: _sources.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.surfaceElevated, height: 1),
              itemBuilder: (c, i) {
                final s = _sources[i];
                final selected = _selected?.url == s.url;
                return ListTile(
                  dense: true,
                  onTap: () {
                    setState(() => _selected = s);
                    Navigator.pop(c);
                  },
                  leading: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? AppColors.accent : AppColors.textMuted,
                      size: 22),
                  title: Text(s.name,
                      style: AppTypography.bodyPrimary.copyWith(
                          fontSize: 13,
                          color: selected
                              ? AppColors.accent
                              : AppColors.textPrimary)),
                  subtitle: Text(s.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.metadata
                          .copyWith(fontSize: 11, color: AppColors.textMuted)),
                  trailing: s.quality != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(s.quality!,
                              style: AppTypography.metadata.copyWith(
                                  fontSize: 11,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600)))
                      : null,
                );
              },
            )),
          ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(fit: StackFit.expand, children: [
          Container(color: Colors.black),
          if (widget.details.backdropUrlW1280.isNotEmpty)
            Positioned.fill(
                child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.5), BlendMode.dstOver),
              child: Image.network(widget.details.backdropUrlW1280,
                  fit: BoxFit.cover),
            )),

          // Center state
          Center(
              child: _loadingSources
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2),
                      const SizedBox(height: 16),
                      Text('Fetching streams…',
                          style: AppTypography.bodyPrimary.copyWith(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ])
                  : _error != null
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.textMuted, size: 48),
                          const SizedBox(height: 12),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: AppTypography.bodyPrimary.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                              onPressed: _loadSources,
                              child: const Text('Retry')),
                        ])
                      : IconButton(
                          icon: Icon(
                              _playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 64,
                              color: AppColors.textPrimary
                                  .withValues(alpha: _showControls ? 1 : 0)),
                          onPressed: _showControls ? _togglePlay : null)),

          // Source label (top-left under back button)
          if (_selected != null && _showControls && !_locked)
            Positioned(
                top: 60,
                left: 16,
                right: 80,
                child: SafeArea(
                    bottom: false,
                    child: Text(_selected!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.metadata.copyWith(
                            color: AppColors.textMuted, fontSize: 11)))),

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
                                      _duration.clamp(0.0001, double.infinity),
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
                                    onPressed:
                                        _selected != null ? _togglePlay : null),
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
                                    icon: const Icon(
                                        Icons.video_settings_rounded,
                                        color: AppColors.textPrimary,
                                        size: 22),
                                    onPressed: _sources.length > 1
                                        ? _openSourceSheet
                                        : null),
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
