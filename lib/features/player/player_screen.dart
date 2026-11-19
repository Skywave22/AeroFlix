import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/tmdb_service.dart';
import '../../core/platform/pip_service.dart';
import '../../core/platform/screen_mode.dart';
import '../../core/utils/trailer_helper.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/stream_source.dart';
import '../../shared/providers/continue_watching_provider.dart';
import '../../shared/providers/download_provider.dart';
import '../../shared/providers/player_controller.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/stream_providers.dart';
import '../providers/provider_diagnostics_screen.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final MediaDetails details;
  final int season;
  final int episode;
  final String? episodeTitle;
  final int resumeAtMs;
  final PlayerArgs? nextEpisode;

  /// When set, plays this local file (offline download) instead of a network stream.
  final String? localFilePath;

  const PlayerScreen({
    super.key,
    required this.details,
    this.season = 0,
    this.episode = 0,
    this.episodeTitle,
    this.resumeAtMs = 0,
    this.nextEpisode,
    this.localFilePath,
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

  static bool _isDirectFile(String url) {
    final u = url.toLowerCase();
    return (u.contains('.mp4') || u.contains('.mkv')) && !u.contains('.m3u8');
  }

  List<StreamSource> _sources = const [];
  StreamSource? _selected;
  bool _loadingSources = true;
  String? _error;

  /// Live progress of the provider search (id -> resolution), so the loading
  /// screen shows which provider is being scraped instead of a bare spinner.
  final Map<String, ProviderResolution> _progress = {};
  StreamSubscription<ProviderResolution>? _resolveSub;
  bool _startedPlayback = false;

  /// Sources that failed to open, so retries/failover never pick them again.
  final Set<String> _deadUrls = {};
  Timer? _startWatchdog;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _bufferingSub;
  bool _buffering = false;
  bool _failingOver = false;
  bool _pendingFailover = false;
  bool _softwareDecode = false;
  Duration _lastAdvancedPos = Duration.zero;
  DateTime _lastAdvanceAt = DateTime.now();
  Timer? _stallTimer;
  Timer? _searchTicker;
  DateTime? _searchStart;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _seeking = false;
  bool _completed = false;
  bool _seekedToResume = false;
  int _autoAdvanceCountdown = 0;
  double _rate = 1.0;
  // Starts at "fill & crop": 16:9 content on a 20:9 phone otherwise shows black
  // bars on both sides, which reads as a broken/empty player.
  int _fitIndex = 1; // 0=contain, 1=cover, 2=fill
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
    // Belt-and-braces: the router applies the player mode when it lands on
    // /player, and `apply` is idempotent, so repeating it here is free — but it
    // guarantees landscape even on the first frame of a cold-start deep link.
    ScreenModeController.apply(ScreenMode.player);
    // Pull persisted defaults from settings once the widget is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(settingsProvider);
      setState(() => _rate = s.defaultSpeed);
    });
    _scheduleHide();
    _loadSources();
    _startProgressSaver();
    WakelockPlus.enable();
    final pip = ref.read(pipServiceProvider);
    pip.setEnabled(true);
    pip.setAutoEnterOnBackground(true);
    pip.addListener(_onPipChanged);
  }

  void _onPipChanged() {
    if (!mounted) return;
    final inPip = ref.read(pipServiceProvider).inPip;
    setState(() {
      _locked = inPip; // lock controls in PiP
      _showControls = !inPip;
    });
    if (inPip) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky,
          overlays: []);
    } else {
      // Leaving PiP: Android resolves the activity back to its unfocused state
      // and drops the requested orientation, so ask for landscape again.
      ScreenModeController.reassert();
    }
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
    await _resolveSub?.cancel();
    _resolveSub = null;
    if (!mounted) return;
    setState(() {
      _loadingSources = true;
      _searchStart = DateTime.now();
      _searchTicker?.cancel();
      _searchTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_loadingSources) return;
        setState(() {});
      });
      _error = null;
      _completed = false;
      _progress.clear();
      _startedPlayback = false;
      _selected = null;
      _sources = const [];
    });

    // Offline playback from a completed download.
    final localPath = widget.localFilePath;
    if (localPath != null) {
      final f = File(localPath);
      if (!await f.exists()) {
        if (!mounted) return;
        setState(() {
          _loadingSources = false;
          _stopSearchTicker();
          _error =
              'The downloaded file is missing. Remove it from Downloads and download it again.';
        });
        return;
      }
      final src = StreamSource(
        url: f.path,
        name: 'Offline · ${widget.details.title}',
        quality: 'Local',
        providerId: 'local',
      );
      _sources = [src];
      setState(() => _selected = src);
      await _play(src);
      if (!mounted) return;
      setState(() {
        _loadingSources = false;
        _stopSearchTicker();
        _startedPlayback = true;
      });
      return;
    }

    // Providers are scraped one at a time (QuickJS is synchronous), so start
    // playing the first link that lands and let the rest keep filling the
    // source list in the background.
    _resolveSub = ref
        .read(streamServiceProvider)
        .resolveStreams(widget.details,
            season: widget.season, episode: widget.episode)
        .listen(
      (res) {
        if (!mounted) return;
        setState(() => _progress[res.providerId] = res);
        if (res.sources.isEmpty) return;
        final merged = <StreamSource>{..._sources, ...res.sources}.toList()
          ..sort(StreamService.compareSources);
        setState(() => _sources = merged);
        if (_pendingFailover) {
          final next = merged.firstWhere(
            (s) => !_deadUrls.contains(s.url),
            orElse: () => res.sources.first,
          );
          _pendingFailover = false;
          _play(next);
          return;
        }
        if (!_startedPlayback) {
          _startedPlayback = true;
          final first = merged.first;
          setState(() {
            _selected = first;
            _loadingSources = false;
            _stopSearchTicker();
          });
          _play(first).catchError((Object e) {
            if (mounted) setState(() => _error = 'Playback failed: $e');
          });
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _loadingSources = false;
          _stopSearchTicker();
          _error = 'Provider search failed: $e';
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _loadingSources = false;
          _stopSearchTicker();
          _pendingFailover = false;
          if (_sources.isEmpty && _error == null) {
            final failures = _progress.entries
                .where((e) => !e.value.ok)
                .map((e) => '${e.key}: ${e.value.error}')
                .toList();
            _error = failures.isEmpty
                ? 'No provider has a working in-app link for this title right now.'
                : 'No working link right now.\n\n${failures.take(3).join('\n')}';
          }
        });
      },
    );
  }

  String get _searchElapsed {
    final start = _searchStart;
    if (start == null) return '0';
    return '${DateTime.now().difference(start).inSeconds}';
  }

  /// Loading / failure panel: shows which provider is being scraped and, when
  /// nothing resolves, gives the user something that actually works.
  void _stopSearchTicker() {
    _searchTicker?.cancel();
    _searchTicker = null;
  }

  Widget _buildCenterState() {
    final ids = ref.read(streamServiceProvider).providers;
    if (_loadingSources) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2)),
          const SizedBox(height: 14),
          Text('Finding a link…',
              style: AppTypography.bodyPrimary.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
              ids.length == 1
                  ? 'Checking every site at once · ${_searchElapsed}s'
                  : '${_progress.length} of ${ids.length} providers checked · ${_searchElapsed}s',
              style: AppTypography.bodyPrimary
                  .copyWith(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 14),
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: _progressRowIcon(_progress[id], id)),
                const SizedBox(width: 10),
                Text(_providerLabel(id),
                    style: AppTypography.bodyPrimary.copyWith(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                Text(_progressStatus(_progress[id]),
                    style: AppTypography.bodyPrimary
                        .copyWith(color: AppColors.textMuted, fontSize: 11)),
              ]),
            ),
        ]),
      );
    }

    // Failure panel.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded,
            color: AppColors.textMuted, size: 40),
        const SizedBox(height: 10),
        Text(_error ?? 'No working source for this title.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyPrimary.copyWith(
                color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
        const SizedBox(height: 18),
        Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                  onPressed: _loadSources,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again')),
              if (trailerUrl(widget.details) != null)
                OutlinedButton.icon(
                    onPressed: () async {
                      context.pop();
                      await openTrailer(widget.details);
                    },
                    icon:
                        const Icon(Icons.play_circle_outline_rounded, size: 18),
                    label: const Text('Watch trailer')),
              if (_sources.length > 1)
                OutlinedButton.icon(
                    onPressed: () {
                      for (final s in _sources) {
                        _deadUrls.remove(s.url);
                      }
                      _softwareDecode = false;
                      _openSourceSheet();
                    },
                    icon: const Icon(Icons.video_settings_rounded, size: 18),
                    label: Text('Sources (${_sources.length})')),
              TextButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ProviderDiagnosticsScreen())),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Provider status')),
            ]),
      ]),
    );
  }

  Widget _progressRowIcon(ProviderResolution? res, String id) {
    if (res == null) {
      return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: AppColors.textMuted));
    }
    if (!res.ok) {
      return const Icon(Icons.close_rounded,
          size: 16, color: Color(0xFFFF6B6B));
    }
    return Icon(
        res.sources.isEmpty ? Icons.remove_rounded : Icons.check_rounded,
        size: 16,
        color: res.sources.isEmpty ? AppColors.textMuted : AppColors.accent);
  }

  String _progressStatus(ProviderResolution? res) {
    if (res == null) return '…';
    if (!res.ok) {
      final e = res.error ?? 'failed';
      return e.length > 28 ? '${e.substring(0, 28)}…' : e;
    }
    return res.sources.isEmpty ? 'no links' : '${res.sources.length} links';
  }

  static String _providerLabel(String id) {
    switch (id) {
      case 'tjaio':
        return 'TJ All-in-one';
      case 'cinezo':
        return 'Cinezo';
      case 'screenscape':
        return 'ScreenScape';
      case 'nxsha':
        return 'Nxsha';
      case 'anihype':
        return 'AniHype';
      case 'katdrama':
        return 'KatDrama';
      default:
        return id;
    }
  }

  Future<void> _play(StreamSource src) async {
    _startWatchdog?.cancel();
    _errorSub?.cancel();
    _bufferingSub?.cancel();
    final ap = await ref
        .read(activePlayerProvider.notifier)
        .play(src, softwareDecode: _softwareDecode);
    ap.player.setRate(_rate);

    // A provider link that opens but never produces a frame (403 from the CDN,
    // expired token, dead mirror) leaves media_kit "buffering" forever. Watch
    // for that and move to the next source on our own.
    _lastAdvancedPos = Duration.zero;
    _lastAdvanceAt = DateTime.now();
    _stallTimer?.cancel();
    _searchTicker?.cancel();
    _stallTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final stalledFor = DateTime.now().difference(_lastAdvanceAt);
      final noProgress = _position == _lastAdvancedPos;
      if (_playing && !_completed && noProgress && stalledFor.inSeconds >= 14) {
        _failover(src, 'playback stalled for ${stalledFor.inSeconds}s');
      }
    });

    _startWatchdog = Timer(const Duration(seconds: 14), () {
      if (!mounted || _deadUrls.contains(src.url)) return;
      if (_duration > Duration.zero || _position > Duration.zero) return;
      _failover(src, 'did not start');
    });
    _errorSub = ap.player.stream.error.listen((message) {
      if (!mounted || message.isEmpty) return;
      _failover(src, message);
    });
    _bufferingSub = ap.player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() => _buffering = b);
      if (!b) return;
      // Still buffering with nothing played for 25 s on this source? Give up on
      // it rather than spinning forever.
      Timer(const Duration(seconds: 25), () {
        if (!mounted) return;
        if (_selected?.url != src.url) return;
        if (_position > Duration.zero) return;
        _failover(src, 'stalled while buffering');
      });
    });
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
          final autoSubs = ref.read(settingsProvider).subtitlesOnByDefault;
          _selectedSub = (autoSubs && subs.isNotEmpty) ? subs.first : null;
          if (_selectedSub != null) {
            ap.player.setSubtitleTrack(_selectedSub!);
          }
          _selectedAudio = audios.isNotEmpty ? audios.first : null;
        }
      });
    });
    _posSub = ap.player.stream.position.listen((p) {
      if (!mounted || _seeking) return;
      if (p > _lastAdvancedPos) {
        _lastAdvancedPos = p;
        _lastAdvanceAt = DateTime.now();
        _startWatchdog?.cancel();
      }
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

  /// Marks [src] dead and moves to the next untried source.
  ///
  /// Providers return a dozen links of wildly different quality of service, so
  /// "this one link doesn't open" must never be a dead end for the user.
  Future<void> _failover(StreamSource src, String reason) async {
    if (_failingOver || !mounted) return;
    if (src.url == widget.localFilePath) {
      return; // offline playback: no alternatives
    }
    _failingOver = true;
    _deadUrls.add(src.url);
    // If hardware decoding couldn't produce a frame, the next source gets
    // decoded on the CPU — otherwise every link would fail the same way.
    _softwareDecode = true;
    _startWatchdog?.cancel();

    final next = _sources.firstWhere(
      (s) => !_deadUrls.contains(s.url),
      orElse: () => src,
    );
    if (next.url == src.url) {
      if (!mounted) return;
      if (_loadingSources) {
        // Providers are still being scraped — hold on for the next batch
        // instead of declaring failure on the first one that misbehaved.
        _pendingFailover = true;
        setState(() {
          _failingOver = false;
          _buffering = true;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
        return;
      }
      setState(() {
        _failingOver = false;
        _buffering = false;
        _error = 'Every source failed to play.\n\n'
            'Last error: $reason\n\nTry again, pick another source from the '
            'list, or watch the trailer.';
      });
      return;
    }

    if (mounted) {
      final msg = '${src.name} failed — trying another source';
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
        _buffering = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
    }
    await _play(next);
    _failingOver = false;
  }

  void _beginAutoAdvanceCountdown() {
    _autoAdvanceTimer?.cancel();
    if (widget.nextEpisode == null) return;
    if (!ref.read(settingsProvider).autoPlayNext) return;
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
    _resolveSub?.cancel();
    _startWatchdog?.cancel();
    _stallTimer?.cancel();
    _errorSub?.cancel();
    _bufferingSub?.cancel();
    final pip = ref.read(pipServiceProvider);
    pip.removeListener(_onPipChanged);
    pip.setEnabled(false);
    pip.setAutoEnterOnBackground(false);
    WakelockPlus.disable();
    // Deliberately does NOT set an orientation here. Popping the player moves
    // the router to a portrait route and the router listener locks portrait —
    // while `pushReplacement` to the next episode keeps the location at
    // /player, so no rotation is triggered mid-playback. Forcing portrait here
    // would (and previously did) fight the incoming player.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Safety net for routes without a location change (e.g. a replaced route
      // disposed after its successor): re-derive the mode from the router.
      final path = appRouter.routerDelegate.currentConfiguration.uri.path;
      ScreenModeController.syncForLocation(path);
    });
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

  void _cycleFit() {
    setState(() {
      _fitIndex = (_fitIndex + 1) % _fits.length;
      _fitToast = _fitLabels[_fitIndex];
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _fitToast = null);
    });
  }

  String _downloadKey() {
    if (widget.details.type == MediaType.tv && widget.season > 0) {
      return 'tv:${widget.details.id}:${widget.season}:${widget.episode}';
    }
    return '${widget.details.type.name}:${widget.details.id}';
  }

  bool _isDownloaded() {
    final d = ref.read(downloadProvider.notifier).byKey(_downloadKey());
    return d?.status == DownloadStatus.completed;
  }

  void _toggleDownload() {
    final n = ref.read(downloadProvider.notifier);
    final key = _downloadKey();
    final title = widget.episodeTitle?.isNotEmpty == true
        ? '${widget.details.title} · ${widget.episodeTitle}'
        : widget.details.title;
    final subtitle = widget.season > 0
        ? 'S${widget.season.toString().padLeft(2, '0')}E${widget.episode.toString().padLeft(2, '0')}'
        : 'Movie';
    if (n.has(key)) {
      n.remove(key);
      _showToast('Removed from downloads');
      return;
    }
    // Offline download copies real bytes, so it needs a single direct file.
    // The currently selected source is used when it is MP4/MKV, otherwise the
    // first direct-file source the providers returned.
    StreamSource? direct;
    if (_selected != null && _isDirectFile(_selected!.url)) {
      direct = _selected;
    } else {
      for (final s in _sources) {
        if (_isDirectFile(s.url)) {
          direct = s;
          break;
        }
      }
    }
    if (direct == null) {
      _showToast(
          'This link is an HLS stream — pick an MP4/MKV source to download offline');
      return;
    }
    final url = direct.url;
    n.enqueue(DownloadItem(
      key: key,
      title: title,
      subtitle: subtitle,
      posterPath: widget.details.posterPath,
      kind: widget.details.type.name,
      mediaId: widget.details.id,
      season: widget.season,
      episode: widget.episode,
      url: url,
    ));
    _showToast('Downloading $title');
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating));
  }

  Widget _buildScrubPreview() {
    final pct = _duration.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    return Align(
        alignment: Alignment(-1.0 + pct * 2.0, 1),
        child: FractionalTranslation(
            translation: const Offset(-0.5, 0),
            child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 130,
                height: 76,
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]),
                clipBehavior: Clip.antiAlias,
                child: Stack(fit: StackFit.expand, children: [
                  if (widget.details.backdropUrlW1280.isNotEmpty)
                    LayoutBuilder(builder: (c, bc) {
                      // Slide the backdrop horizontally to suggest position.
                      final shift = (1.0 - pct) * (bc.maxWidth * 2);
                      return OverflowBox(
                          minWidth: bc.maxWidth * 2,
                          maxWidth: bc.maxWidth * 2,
                          alignment: Alignment.centerLeft,
                          child: Transform.translate(
                              offset: Offset(-shift, 0),
                              child: Image.network(
                                  widget.details.backdropUrlW1280,
                                  fit: BoxFit.cover,
                                  width: bc.maxWidth * 2,
                                  height: bc.maxHeight)));
                    }),
                  Container(color: Colors.black.withValues(alpha: 0.35)),
                  Center(
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(_fmt(_position),
                              style: AppTypography.metadata.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)))),
                ]))));
  }

  Future<void> _shareCurrent() async {
    final d = widget.details;
    final kind = d.type == MediaType.tv ? 'tv' : 'movie';
    final ep = d.type == MediaType.tv && widget.season > 0
        ? ' S${widget.season.toString().padLeft(2, "0")}E${widget.episode.toString().padLeft(2, "0")}'
        : '';
    final title = '${d.title}$ep';
    final url = 'https://www.themoviedb.org/$kind/${d.id}';
    await Share.share('Watch "$title" on AeroFlix\n$url', subject: title);
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

  /// Remote/keyboard control: centre = play/pause, left/right = ±10 s,
  /// up/down = show controls, back = leave (handled by the router).
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.mediaPlayPause:
        _togglePlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.mediaRewind:
        _seekRelative(const Duration(seconds: -10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.mediaFastForward:
        _seekRelative(const Duration(seconds: 10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowDown:
        setState(() => _showControls = true);
        _scheduleHide();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _seekRelative(Duration delta) {
    final target = _position + delta;
    final clamped = Duration(
        milliseconds: target.inMilliseconds.clamp(
            0,
            _duration.inMilliseconds > 0
                ? _duration.inMilliseconds
                : target.inMilliseconds));
    ref.read(activePlayerProvider)?.player.seek(clamped);
    setState(() => _position = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activePlayerProvider);
    final hasVideo = active != null && _selected != null;

    return Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Scaffold(
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
                            Colors.black
                                .withValues(alpha: hasVideo ? 0.75 : 0.5),
                            BlendMode.dstOver),
                        child: Image.network(widget.details.backdropUrlW1280,
                            fit: BoxFit.cover))),

              // Buffering pill (a source that plays but starves)
              if (hasVideo && _buffering && !_loadingSources && _error == null)
                Positioned(
                    top: 16,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: Colors.white)),
                        const SizedBox(width: 8),
                        Text('Buffering…',
                            style: AppTypography.metadata
                                .copyWith(color: Colors.white, fontSize: 11)),
                      ]),
                    )),

              // Center state
              if (!hasVideo || _loadingSources || _error != null)
                Positioned.fill(child: Center(child: _buildCenterState())),
              if (hasVideo && !_loadingSources && _error == null)
                Positioned.fill(
                    child: Center(
                        child: IconButton(
                            icon: Icon(
                                _completed
                                    ? Icons.replay_rounded
                                    : _playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                size: 64,
                                color: AppColors.textPrimary
                                    .withValues(alpha: _showControls ? 1 : 0)),
                            onPressed: _showControls ? _togglePlay : null))),

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
                                  color:
                                      AppColors.accent.withValues(alpha: 0.5))),
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
                                          color: AppColors.accent,
                                          fontSize: 11)),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(_fitToast!,
                            style: AppTypography.bodyPrimary
                                .copyWith(fontSize: 13)))),

              // Next-up card (always visible when nextEpisode available and controls showing)
              if (widget.nextEpisode != null &&
                  _showControls &&
                  !_locked &&
                  !_loadingSources &&
                  _error == null &&
                  !_buffering &&
                  _autoAdvanceCountdown == 0)
                Positioned(
                    bottom: 170,
                    left: 16,
                    right: 16,
                    child: _NextUpCard(
                        episode: widget.nextEpisode!, onPlay: _playNext)),

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
                                colors: [
                              AppColors.overlay70,
                              Colors.transparent
                            ])),
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
                        child: SafeArea(
                            bottom: false,
                            child: Row(children: [
                              IconButton(
                                  tooltip: 'Go back',
                                  icon: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      size: 20,
                                      color: AppColors.textPrimary),
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
                                  tooltip: _locked
                                      ? 'Unlock controls'
                                      : 'Lock controls',
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
                                colors: [
                              Colors.transparent,
                              AppColors.overlay70
                            ])),
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: SafeArea(
                            top: false,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_seeking) _buildScrubPreview(),
                                  SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 3,
                                        thumbShape: const RoundSliderThumbShape(
                                            enabledThumbRadius: 6),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                                overlayRadius: 12),
                                        activeTrackColor: AppColors.accent,
                                        inactiveTrackColor:
                                            AppColors.surfaceElevated,
                                        thumbColor: AppColors.accent,
                                      ),
                                      child: Slider(
                                        value: _duration.inMilliseconds == 0
                                            ? 0
                                            : (_position.inMilliseconds /
                                                    _duration.inMilliseconds)
                                                .clamp(0.0, 1.0),
                                        onChangeStart: (_) {
                                          setState(() => _seeking = true);
                                          _hideTimer?.cancel();
                                        },
                                        onChangeEnd: (v) {
                                          setState(() => _seeking = false);
                                          final ap =
                                              ref.read(activePlayerProvider);
                                          if (ap != null) {
                                            ap.player.seek(_duration * v);
                                          }
                                          _cancelAutoAdvance();
                                          _scheduleHide();
                                        },
                                        onChanged: (v) {
                                          setState(
                                              () => _position = _duration * v);
                                        },
                                      )),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Row(children: [
                                        Text(_fmt(_position),
                                            style: AppTypography.metadata
                                                .copyWith(
                                                    color:
                                                        AppColors.textSecondary,
                                                    fontSize: 11)),
                                        const Spacer(),
                                        Text(_fmt(_duration),
                                            style: AppTypography.metadata
                                                .copyWith(
                                                    color:
                                                        AppColors.textSecondary,
                                                    fontSize: 11)),
                                      ])),
                                  const SizedBox(height: 4),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        IconButton(
                                            tooltip: 'Back 10 seconds',
                                            icon: const Icon(
                                                Icons.replay_10_rounded,
                                                color: AppColors.textPrimary,
                                                size: 28),
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
                                                    ? Icons
                                                        .replay_circle_filled_rounded
                                                    : _playing
                                                        ? Icons
                                                            .pause_circle_filled_rounded
                                                        : Icons
                                                            .play_circle_fill_rounded,
                                                color: AppColors.textPrimary,
                                                size: 48),
                                            onPressed: _selected != null
                                                ? _togglePlay
                                                : null),
                                        IconButton(
                                            icon: Icon(Icons.skip_next_rounded,
                                                color:
                                                    widget.nextEpisode != null
                                                        ? AppColors.textPrimary
                                                        : AppColors.textMuted,
                                                size: 28),
                                            onPressed:
                                                widget.nextEpisode != null
                                                    ? _playNext
                                                    : null),
                                        IconButton(
                                            tooltip: 'Forward 10 seconds',
                                            icon: const Icon(
                                                Icons.forward_10_rounded,
                                                color: AppColors.textPrimary,
                                                size: 28),
                                            onPressed: () => _seekRel(10)),
                                        const Spacer(),
                                        IconButton(
                                            tooltip:
                                                'Download for offline viewing',
                                            icon: Icon(Icons.download_outlined,
                                                color: _isDownloaded()
                                                    ? AppColors.success
                                                    : AppColors.textPrimary,
                                                size: 22),
                                            onPressed: _toggleDownload),
                                        IconButton(
                                            tooltip: 'Share this title',
                                            icon: const Icon(
                                                Icons.share_outlined,
                                                color: AppColors.textPrimary,
                                                size: 22),
                                            onPressed: _shareCurrent),
                                        IconButton(
                                            tooltip: 'Picture in picture',
                                            icon: const Icon(
                                                Icons
                                                    .picture_in_picture_alt_rounded,
                                                color: AppColors.textPrimary,
                                                size: 22),
                                            onPressed: () async {
                                              final pip =
                                                  ref.read(pipServiceProvider);
                                              final ok = await pip.enterPip();
                                              if (!ok && mounted) {
                                                _showToast(pip.supported
                                                    ? 'Background playback is enabled'
                                                    : 'Picture-in-Picture not available on this device');
                                              }
                                            }),
                                        IconButton(
                                            tooltip: 'Subtitles',
                                            icon: Icon(
                                                _selectedSub != null
                                                    ? Icons
                                                        .closed_caption_rounded
                                                    : Icons
                                                        .closed_caption_off_rounded,
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
                                            tooltip: 'Audio track',
                                            icon: Icon(Icons.audiotrack_rounded,
                                                color: _audios.length > 1
                                                    ? AppColors.textPrimary
                                                    : AppColors.textMuted,
                                                size: 22),
                                            onPressed: _audios.length > 1
                                                ? _openAudioSheet
                                                : null),
                                        IconButton(
                                            tooltip: 'Choose source',
                                            icon: const Icon(
                                                Icons.video_settings_rounded,
                                                color: AppColors.textPrimary,
                                                size: 22),
                                            onPressed: _sources.length > 1
                                                ? _openSourceSheet
                                                : null),
                                        IconButton(
                                            tooltip: 'Playback speed',
                                            icon: Icon(Icons.speed_rounded,
                                                color: _rate != 1.0
                                                    ? AppColors.accent
                                                    : AppColors.textPrimary,
                                                size: 22),
                                            onPressed: _openSpeedSheet),
                                        IconButton(
                                            tooltip: 'Resize video',
                                            icon: Icon(Icons.fit_screen_rounded,
                                                color: _fitIndex != 0
                                                    ? AppColors.accent
                                                    : AppColors.textPrimary,
                                                size: 22),
                                            onPressed: _cycleFit),
                                      ]),
                                ])),
                      ))),
              // Double-tap seek zones (left = -10s, right = +10s)
              if (_showControls || !_locked)
                Positioned.fill(
                    child: Row(children: [
                  Expanded(
                      child: _DoubleTapZone(
                          icon: Icons.replay_10_rounded,
                          onDoubleTap: () => _seekRel(-10))),
                  const Expanded(child: SizedBox()),
                  Expanded(
                      child: _DoubleTapZone(
                          icon: Icons.forward_10_rounded,
                          onDoubleTap: () => _seekRel(10))),
                ])),
              // Episode strip (TV only)
              if (widget.details.type == MediaType.tv &&
                  widget.season > 0 &&
                  _showControls &&
                  !_locked)
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 120,
                    child: _EpisodeStrip(
                        tvId: widget.details.id,
                        season: widget.season,
                        currentEpisode: widget.episode,
                        onTap: (ep) {
                          if (ep.episodeNumber == widget.episode) return;
                          _persistProgress();
                          context.pushReplacement('/player',
                              extra: PlayerArgs(
                                  details: widget.details,
                                  season: widget.season,
                                  episode: ep.episodeNumber,
                                  episodeTitle: ep.name,
                                  resumeAtMs: 0));
                        })),
            ]),
          ),
        ));
  }
}

class _NextUpCard extends StatelessWidget {
  final PlayerArgs episode;
  final VoidCallback onPlay;
  const _NextUpCard({required this.episode, required this.onPlay});
  @override
  Widget build(BuildContext context) {
    final title = episode.episodeTitle ?? 'Next episode';
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
        child: Row(children: [
          Container(
              width: 74,
              height: 48,
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6)),
              clipBehavior: Clip.antiAlias,
              child: (episode.details.backdropUrlW1280.isNotEmpty ||
                      episode.details.posterPath != null)
                  ? Image.network(
                      episode.details.backdropUrlW1280.isNotEmpty
                          ? episode.details.backdropUrlW1280
                          : 'https://image.tmdb.org/t/p/w342${episode.details.posterPath}',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          color: AppColors.surface,
                          child: const Icon(Icons.movie_creation_outlined,
                              color: AppColors.textMuted, size: 20)))
                  : Container(
                      color: AppColors.surface,
                      child: const Icon(Icons.movie_creation_outlined,
                          color: AppColors.textMuted, size: 20))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Next up',
                    style: AppTypography.metadata.copyWith(
                        color: AppColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Text(
                    'S${episode.season.toString().padLeft(2, '0')}E${episode.episode.toString().padLeft(2, '0')} · $title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyPrimary
                        .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(episode.details.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.metadata
                        .copyWith(color: AppColors.textMuted, fontSize: 11)),
              ])),
          IconButton(
              onPressed: onPlay,
              icon: const Icon(Icons.play_circle_fill_rounded,
                  color: AppColors.textPrimary, size: 36),
              splashRadius: 22),
        ]));
  }
}

class _DoubleTapZone extends StatefulWidget {
  final IconData icon;
  final VoidCallback onDoubleTap;
  const _DoubleTapZone({required this.icon, required this.onDoubleTap});
  @override
  State<_DoubleTapZone> createState() => _DoubleTapZoneState();
}

class _DoubleTapZoneState extends State<_DoubleTapZone> {
  bool _flash = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () {
        widget.onDoubleTap();
        setState(() => _flash = true);
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) setState(() => _flash = false);
        });
      },
      child: Center(
          child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _flash ? 1 : 0,
              child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle),
                  child: Icon(widget.icon, color: Colors.white, size: 36)))),
    );
  }
}

class _EpisodeStrip extends ConsumerStatefulWidget {
  final int tvId, season, currentEpisode;
  final void Function(Episode) onTap;
  const _EpisodeStrip(
      {required this.tvId,
      required this.season,
      required this.currentEpisode,
      required this.onTap});
  @override
  ConsumerState<_EpisodeStrip> createState() => _EpisodeStripState();
}

class _EpisodeStripState extends ConsumerState<_EpisodeStrip> {
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async =
        ref.watch(seasonEpisodesProvider('${widget.tvId}:${widget.season}'));
    return async.when(
        loading: () => const SizedBox(height: 80),
        error: (_, __) => const SizedBox(height: 80),
        data: (eps) {
          if (eps.length < 2) return const SizedBox(height: 80);
          final controller = _scroll ??= ScrollController(
              initialScrollOffset:
                  (widget.currentEpisode - 1).clamp(0, eps.length - 1) * 110.0);
          return SizedBox(
              height: 92,
              child: ListView.separated(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.horizontalPadding),
                  physics: const BouncingScrollPhysics(),
                  itemCount: eps.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final ep = eps[i];
                    final active = ep.episodeNumber == widget.currentEpisode;
                    return _EpisodeThumb(
                        ep: ep, active: active, onTap: () => widget.onTap(ep));
                  }));
        });
  }
}

class _EpisodeThumb extends StatelessWidget {
  final Episode ep;
  final bool active;
  final VoidCallback onTap;
  const _EpisodeThumb(
      {required this.ep, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            width: 120,
            decoration: BoxDecoration(
                borderRadius: AppRadii.smRadius,
                border: Border.all(
                    color: active
                        ? AppColors.accent
                        : Colors.white.withValues(alpha: 0.08),
                    width: active ? 2 : 1)),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              if (ep.stillUrl.isNotEmpty)
                Image.network(ep.stillUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surface,
                        child: const Icon(Icons.videocam,
                            color: AppColors.textMuted, size: 24)))
              else
                Container(color: AppColors.surface),
              Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85)
                  ]))),
              Positioned(
                  left: 6,
                  right: 6,
                  bottom: 4,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('E${ep.episodeNumber}',
                            style: AppTypography.metadata.copyWith(
                                color: active
                                    ? AppColors.accent
                                    : AppColors.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                        Text(ep.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.metadata.copyWith(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ])),
            ])));
  }
}
