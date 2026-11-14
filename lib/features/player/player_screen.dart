import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';
import '../../shared/providers/continue_watching_provider.dart';
import '../../shared/providers/player_controller.dart';
import '../../shared/providers/stream_providers.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final MediaDetails details;
  final int season;
  final int episode;
  final String? episodeTitle;
  final int resumeAtMs;
  final PlayerArgs? nextEpisode;

  const PlayerScreen({
    super.key,
    required this.details,
    this.season = 0,
    this.episode = 0,
    this.episodeTitle,
    this.resumeAtMs = 0,
    this.nextEpisode,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showControls = true;
  bool _locked = false;
  Timer? _hideTimer;
  Timer? _progressSaveTimer;
  Timer? _autoAdvanceTimer;

  List<StreamSource> _sources = const [];
  StreamSource? _selected;
  bool _loadingSources = true;
  String? _error;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _seeking = false;
  bool _completed = false;
  bool _seekedToResume = false;
  int _autoAdvanceCountdown = 0;
  double _rate = 1.0;
  int _fitIndex = 0; // 0=contain, 1=cover, 2=fill
  String? _fitToast;
  List<mk.SubtitleTrack> _subs = const [];
  mk.SubtitleTrack? _selectedSub; // null = off
  bool _subsLoaded = false;
  List<mk.AudioTrack> _audios = const [];
  mk.AudioTrack? _selectedAudio;

  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const _fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
  static const _fitLabels = ['Fit to screen', 'Fill & crop', 'Stretch'];

  StreamSubscription? _posSub, _durSub, _playSub, _completeSub, _tracksSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _scheduleHide();
    _loadSources();
    _startProgressSaver();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing && !_locked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _startProgressSaver() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _persistProgress();
    });
  }

  void _persistProgress() {
    if (_duration.inMilliseconds <= 0) return;
    final posMs = _position.inMilliseconds;
    final durMs = _duration.inMilliseconds;
    if (posMs <= 0) return;
    ref.read(continueWatchingProvider.notifier).saveProgress(
          type: widget.details.type,
          id: widget.details.id,
          title: widget.details.title,
          posterPath: widget.details.posterPath,
          backdropPath: widget.details.backdropPath,
          season: widget.season,
          episode: widget.episode,
          episodeTitle: widget.episodeTitle,
          positionMs: posMs,
          durationMs: durMs,
        );
  }

  Future<void> _loadSources() async {
    setState(() {
      _loadingSources = true;
      _error = null;
      _completed = false;
    });
    try {
      final svc = ref.read(streamServiceProvider);
      final list = await svc.getAllStreams(widget.details,
          season: widget.season, episode: widget.episode);
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _loadingSources = false;
          _error = 'No streams found.';
        });
        return;
      }
      list.sort((a, b) => _qRank(b.quality).compareTo(_qRank(a.quality)));
      _sources = list;
      await _play(list.first);
      setState(() {
        _loadingSources = false;
        _selected = list.first;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSources = false;
        _error = 'Failed to load streams: $e';
      });
    }
  }

  Future<void> _play(StreamSource src) async {
    final ap = await ref.read(activePlayerProvider.notifier).play(src);
    ap.player.setRate(_rate);
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _completeSub?.cancel();
    _tracksSub?.cancel();
    _seekedToResume = false;
    _subsLoaded = false;
    _tracksSub = ap.player.stream.tracks.listen((t) {
      final subs =
          t.subtitle.where((s) => s.id != 'no' && s.id != 'auto').toList();
      final audios = t.audio.where((a) => a.id != 'auto').toList();
      if (!mounted) return;
      setState(() {
        _subs = subs;
        _audios = audios;
        if (!_subsLoaded) {
          _subsLoaded = true;
          _selectedSub = null;
          _selectedAudio = audios.isNotEmpty ? audios.first : null;
        }
      });
    });
    _posSub = ap.player.stream.position.listen((p) {
      if (!mounted || _seeking) return;
      setState(() => _position = p);
      if (!_seekedToResume &&
          widget.resumeAtMs > 0 &&
          p.inMilliseconds < 500 &&
          _duration.inMilliseconds > 0) {
        _seekedToResume = true;
        final target = Duration(
            milliseconds:
                widget.resumeAtMs.clamp(0, _duration.inMilliseconds - 2000));
        if (target > Duration.zero) {
          ap.player.seek(target);
          setState(() => _position = target);
        }
      }
    });
    _durSub = ap.player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _playSub = ap.player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
    _completeSub = ap.player.stream.completed.listen((c) {
      if (c && mounted) {
        setState(() {
          _playing = false;
          _completed = true;
          _position = _duration;
        });
        _persistProgress();
        _beginAutoAdvanceCountdown();
      }
    });
    setState(() => _selected = src);
  }

  void _beginAutoAdvanceCountdown() {
    _autoAdvanceTimer?.cancel();
    if (widget.nextEpisode == null) return;
    setState(() => _autoAdvanceCountdown = 10);
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _autoAdvanceCountdown -= 1);
      if (_autoAdvanceCountdown <= 1) {
        t.cancel();
        _playNext();
      }
    });
  }

  void _cancelAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    setState(() => _autoAdvanceCountdown = 0);
  }

  void _playNext() {
    _autoAdvanceTimer?.cancel();
    final next = widget.nextEpisode;
    if (next == null || !mounted) return;
    // Replace the current route with the next player
    context.pushReplacement('/player', extra: next);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _progressSaveTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _persistProgress();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _completeSub?.cancel();
    _tracksSub?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _togglePlay() {
    final ap = ref.read(activePlayerProvider);
    if (ap == null) return;
    ap.player.playOrPause();
    if (_completed && widget.nextEpisode != null) {
      _playNext();
      return;
    }
    _cancelAutoAdvance();
    _scheduleHide();
  }

  void _seekRel(int deltaSec) {
    final ap = ref.read(activePlayerProvider);
    if (ap == null) return;
    var t = _position + Duration(seconds: deltaSec);
    if (t < Duration.zero) t = Duration.zero;
    if (t > _duration) t = _duration;
    ap.player.seek(t);
    _cancelAutoAdvance();
    _scheduleHide();
  }

  void _onTap() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  String _label() {
    if (widget.details.type == MediaType.tv && widget.season > 0) {
      final ep = widget.episodeTitle ?? 'Episode ${widget.episode}';
      return '${widget.details.title} · S${widget.season.toString().padLeft(2, '0')}E${widget.episode.toString().padLeft(2, '0')} · $ep';
    }
    return widget.details.title;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
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

  void _cycleFit() {
    setState(() {
      _fitIndex = (_fitIndex + 1) % _fits.length;
      _fitToast = _fitLabels[_fitIndex];
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _fitToast = null);
    });
  }

  void _openSpeedSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Playback Speed', style: AppTypography.sectionHeading)),
        for (final r in _rates)
          ListTile(
            dense: true,
            onTap: () {
              Navigator.pop(context);
              final ap = ref.read(activePlayerProvider);
              if (ap != null) {
                ap.player.setRate(r);
                setState(() => _rate = r);
              }
            },
            leading: Icon(
                _rate == r
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: _rate == r ? AppColors.accent : AppColors.textMuted,
                size: 22),
            title: Text('${r}x',
                style: AppTypography.bodyPrimary.copyWith(
                    fontSize: 14,
                    color:
                        _rate == r ? AppColors.accent : AppColors.textPrimary)),
          ),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _openCaptionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Subtitles', style: AppTypography.sectionHeading)),
        ListTile(
          dense: true,
          onTap: () {
            final ap = ref.read(activePlayerProvider);
            ap?.player.setSubtitleTrack(mk.SubtitleTrack.no());
            setState(() => _selectedSub = null);
            Navigator.pop(context);
          },
          leading: Icon(
              _selectedSub == null
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color:
                  _selectedSub == null ? AppColors.accent : AppColors.textMuted,
              size: 22),
          title: Text('Off',
              style: AppTypography.bodyPrimary.copyWith(
                  fontSize: 14,
                  color: _selectedSub == null
                      ? AppColors.accent
                      : AppColors.textPrimary)),
        ),
        for (final s in _subs)
          ListTile(
            dense: true,
            onTap: () {
              final ap = ref.read(activePlayerProvider);
              ap?.player.setSubtitleTrack(s);
              setState(() => _selectedSub = s);
              Navigator.pop(context);
            },
            leading: Icon(
                _selectedSub?.id == s.id
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: _selectedSub?.id == s.id
                    ? AppColors.accent
                    : AppColors.textMuted,
                size: 22),
            title: Text(_subLabel(s),
                style: AppTypography.bodyPrimary.copyWith(
                    fontSize: 14,
                    color: _selectedSub?.id == s.id
                        ? AppColors.accent
                        : AppColors.textPrimary)),
          ),
        const SizedBox(height: 8),
      ])),
    );
  }

  String _subLabel(mk.SubtitleTrack s) {
    final title = s.title ?? '';
    final lang = s.language ?? '';
    if (title.isNotEmpty && title != lang) {
      return '$title${lang.isNotEmpty ? ' ($lang)' : ''}';
    }
    return lang.isNotEmpty ? lang : 'Subtitle ${s.id}';
  }

  String _audioLabel(mk.AudioTrack a) {
    final title = a.title ?? '';
    final lang = a.language ?? '';
    if (lang.isNotEmpty && title.isNotEmpty && title != lang) {
      return '$lang · $title';
    }
    if (lang.isNotEmpty) return lang;
    if (title.isNotEmpty) return title;
    return 'Audio ${a.id}';
  }

  void _openAudioSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Audio', style: AppTypography.sectionHeading)),
        for (final a in _audios)
          ListTile(
            dense: true,
            onTap: () {
              final ap = ref.read(activePlayerProvider);
              ap?.player.setAudioTrack(a);
              setState(() => _selectedAudio = a);
              Navigator.pop(context);
            },
            leading: Icon(
                _selectedAudio?.id == a.id
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: _selectedAudio?.id == a.id
                    ? AppColors.accent
                    : AppColors.textMuted,
                size: 22),
            title: Text(_audioLabel(a),
                style: AppTypography.bodyPrimary.copyWith(
                    fontSize: 14,
                    color: _selectedAudio?.id == a.id
                        ? AppColors.accent
                        : AppColors.textPrimary)),
          ),
        const SizedBox(height: 8),
      ])),
    );
  }

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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child:
                    Text('Select Source', style: AppTypography.sectionHeading)),
            if (_selected != null)
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Now: ${_selected!.name}',
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
                final sel = _selected?.url == s.url;
                return ListTile(
                  dense: true,
                  onTap: () {
                    Navigator.pop(c);
                    _cancelAutoAdvance();
                    _play(s);
                  },
                  leading: Icon(
                      sel
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: sel ? AppColors.accent : AppColors.textMuted,
                      size: 22),
                  title: Text(s.name,
                      style: AppTypography.bodyPrimary.copyWith(
                          fontSize: 13,
                          color:
                              sel ? AppColors.accent : AppColors.textPrimary)),
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
    final active = ref.watch(activePlayerProvider);
    final hasVideo = active != null && _selected != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: Stack(fit: StackFit.expand, children: [
          Container(color: Colors.black),
          if (hasVideo)
            Positioned.fill(
                child: Video(
                    controller: active.controller,
                    fit: _fits[_fitIndex],
                    fill: Colors.black)),
          if ((!hasVideo || _loadingSources) &&
              widget.details.backdropUrlW1280.isNotEmpty)
            Positioned.fill(
                child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: hasVideo ? 0.75 : 0.5),
                        BlendMode.dstOver),
                    child: Image.network(widget.details.backdropUrlW1280,
                        fit: BoxFit.cover))),

          // Center state
          Center(
              child: _loadingSources
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2),
                      const SizedBox(height: 16),
                      Text('Fetching streams…',
                          style: AppTypography.bodyPrimary.copyWith(
                              color: AppColors.textSecondary, fontSize: 13))
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
                              child: const Text('Retry'))
                        ])
                      : IconButton(
                          icon: Icon(
                              _completed
                                  ? Icons.replay_rounded
                                  : _playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                              size: 64,
                              color: AppColors.textPrimary
                                  .withValues(alpha: _showControls ? 1 : 0)),
                          onPressed: _showControls ? _togglePlay : null)),

          // Auto-advance overlay
          if (_completed &&
              widget.nextEpisode != null &&
              _autoAdvanceCountdown > 0)
            Positioned(
                bottom: 120,
                right: 24,
                child: GestureDetector(
                  onTap: _playNext,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.5))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.skip_next_rounded,
                            color: AppColors.accent, size: 22),
                        const SizedBox(width: 8),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Next up',
                                  style: AppTypography.metadata.copyWith(
                                      color: AppColors.textMuted,
                                      fontSize: 11)),
                              Text(
                                  widget.nextEpisode!.episodeTitle ??
                                      'Next episode',
                                  style: AppTypography.bodyPrimary.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text('Playing in $_autoAdvanceCountdown…',
                                  style: AppTypography.metadata.copyWith(
                                      color: AppColors.accent, fontSize: 11)),
                            ]),
                        const SizedBox(width: 12),
                        TextButton(
                            onPressed: _cancelAutoAdvance,
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.textMuted,
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4)),
                            child: const Text('Cancel')),
                      ])),
                )),

          // Source label
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

          // Fit toast
          if (_fitToast != null)
            Center(
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_fitToast!,
                        style:
                            AppTypography.bodyPrimary.copyWith(fontSize: 13)))),

          // Resume-toast
          if (widget.resumeAtMs > 5000 && !_seekedToResume && hasVideo)
            Positioned(
                top: 90,
                right: 20,
                child: SafeArea(
                    bottom: false,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(
                            'Resuming at ${_fmt(Duration(milliseconds: widget.resumeAtMs))}',
                            style: AppTypography.metadata.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11))))),

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
                              onPressed: () {
                                _persistProgress();
                                Navigator.of(context).pop();
                              },
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
                                value: _duration.inMilliseconds == 0
                                    ? 0
                                    : (_position.inMilliseconds /
                                            _duration.inMilliseconds)
                                        .clamp(0.0, 1.0),
                                onChangeStart: (_) => _seeking = true,
                                onChangeEnd: (v) {
                                  _seeking = false;
                                  final ap = ref.read(activePlayerProvider);
                                  if (ap != null) ap.player.seek(_duration * v);
                                  _cancelAutoAdvance();
                                  _scheduleHide();
                                },
                                onChanged: (v) {
                                  setState(() => _position = _duration * v);
                                },
                              )),
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
                                    onPressed: () => _seekRel(-10)),
                                IconButton(
                                    icon: const Icon(
                                        Icons.skip_previous_rounded,
                                        color: AppColors.textMuted,
                                        size: 28),
                                    onPressed: null),
                                IconButton(
                                    icon: Icon(
                                        _completed
                                            ? Icons.replay_circle_filled_rounded
                                            : _playing
                                                ? Icons
                                                    .pause_circle_filled_rounded
                                                : Icons
                                                    .play_circle_fill_rounded,
                                        color: AppColors.textPrimary,
                                        size: 48),
                                    onPressed:
                                        _selected != null ? _togglePlay : null),
                                IconButton(
                                    icon: Icon(Icons.skip_next_rounded,
                                        color: widget.nextEpisode != null
                                            ? AppColors.textPrimary
                                            : AppColors.textMuted,
                                        size: 28),
                                    onPressed: widget.nextEpisode != null
                                        ? _playNext
                                        : null),
                                IconButton(
                                    icon: const Icon(Icons.forward_10_rounded,
                                        color: AppColors.textPrimary, size: 28),
                                    onPressed: () => _seekRel(10)),
                                const Spacer(),
                                IconButton(
                                    icon: Icon(
                                        _selectedSub != null
                                            ? Icons.closed_caption_rounded
                                            : Icons.closed_caption_off_rounded,
                                        color: _selectedSub != null ||
                                                _subs.isNotEmpty
                                            ? (_selectedSub != null
                                                ? AppColors.accent
                                                : AppColors.textPrimary)
                                            : AppColors.textMuted,
                                        size: 22),
                                    onPressed: _subs.isNotEmpty
                                        ? _openCaptionsSheet
                                        : null),
                                IconButton(
                                    icon: Icon(Icons.audiotrack_rounded,
                                        color: _audios.length > 1
                                            ? AppColors.textPrimary
                                            : AppColors.textMuted,
                                        size: 22),
                                    onPressed: _audios.length > 1
                                        ? _openAudioSheet
                                        : null),
                                IconButton(
                                    icon: const Icon(
                                        Icons.video_settings_rounded,
                                        color: AppColors.textPrimary,
                                        size: 22),
                                    onPressed: _sources.length > 1
                                        ? _openSourceSheet
                                        : null),
                                IconButton(
                                    icon: Icon(Icons.speed_rounded,
                                        color: _rate != 1.0
                                            ? AppColors.accent
                                            : AppColors.textPrimary,
                                        size: 22),
                                    onPressed: _openSpeedSheet),
                                IconButton(
                                    icon: Icon(Icons.fit_screen_rounded,
                                        color: _fitIndex != 0
                                            ? AppColors.accent
                                            : AppColors.textPrimary,
                                        size: 22),
                                    onPressed: _cycleFit),
                              ]),
                        ])),
                  ))),
        ]),
      ),
    );
  }
}
