import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DownloadStatus { queued, downloading, paused, completed, failed }

class DownloadItem {
  final String key; // 'movie:id' or 'tv:id:s:e'
  final String title;
  final String subtitle;
  final String? posterPath;
  final String kind;
  final int mediaId;
  final int season, episode;
  final int sizeBytes;
  DownloadStatus status;
  double progress;
  String? error;
  DownloadItem({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.posterPath,
    required this.kind,
    required this.mediaId,
    required this.season,
    required this.episode,
    this.sizeBytes = 0,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.error,
  });

  String get sizeLabel {
    if (sizeBytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = sizeBytes.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(u == 0 ? 0 : 1)} ${units[u]}';
  }
}

/// Simulated download manager: progresses items from queued to completed over
/// ~12 seconds, persists the list across restarts. Replace _tick() with a real
/// Dio download when stream URLs permit byte-range fetches.
class DownloadNotifier extends StateNotifier<List<DownloadItem>> {
  Timer? _t;
  static const _prefsKey = 'aeroflix.downloads';
  DownloadNotifier() : super(const []) {
    _load();
    _t = Timer.periodic(const Duration(milliseconds: 400), (_) => _tick());
  }

  Future<void> _load() async {
    // We don't fully round-trip simulated progress; restore completed set so
    // downloaded movies/shows persist across launches.
    final p = await SharedPreferences.getInstance();
    final keys = p.getStringList(_prefsKey) ?? const [];
    state = [
      for (final k in keys)
        DownloadItem(
          key: k,
          title: k.startsWith('tv:') ? 'Saved episode' : 'Saved movie',
          subtitle: 'Downloaded',
          posterPath: null,
          kind: k.startsWith('tv:') ? 'tv' : 'movie',
          mediaId: int.tryParse(k.split(':')[1]) ?? 0,
          season: 0,
          episode: 0,
          status: DownloadStatus.completed,
          progress: 1,
        )
    ];
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        _prefsKey, state.where((d) => d.status == DownloadStatus.completed).map((d) => d.key).toList());
  }

  void _tick() {
    if (state.isEmpty) return;
    var changed = false;
    final next = <DownloadItem>[];
    for (final d in state) {
      if (d.status == DownloadStatus.downloading) {
        final np = (d.progress + 0.012).clamp(0.0, 1.0);
        next.add(d..progress = np);
        if (np >= 1.0) d.status = DownloadStatus.completed;
        changed = true;
      } else {
        next.add(d);
      }
    }
    if (changed) {
      state = next;
      // Kick off first queued item if none currently downloading
      if (!state.any((d) => d.status == DownloadStatus.downloading)) {
        final qi = state.indexWhere((d) => d.status == DownloadStatus.queued);
        if (qi >= 0) state[qi].status = DownloadStatus.downloading;
      }
      _save();
    }
  }

  bool enqueue(DownloadItem item) {
    if (state.any((d) => d.key == item.key)) return false;
    item.status = state.any((d) => d.status == DownloadStatus.downloading)
        ? DownloadStatus.queued
        : DownloadStatus.downloading;
    state = [item, ...state];
    _save();
    return true;
  }

  void remove(String key) {
    state = state.where((d) => d.key != key).toList();
    _save();
  }

  void pause(String key) {
    final i = state.indexWhere((d) => d.key == key);
    if (i < 0) return;
    if (state[i].status == DownloadStatus.downloading ||
        state[i].status == DownloadStatus.queued) {
      state[i].status = DownloadStatus.paused;
      state = [...state];
    }
  }

  void resume(String key) {
    final i = state.indexWhere((d) => d.key == key);
    if (i < 0) return;
    state[i].status = state.any((d) => d.status == DownloadStatus.downloading)
        ? DownloadStatus.queued
        : DownloadStatus.downloading;
    state = [...state];
  }

  void retry(String key) {
    final i = state.indexWhere((d) => d.key == key);
    if (i < 0) return;
    state[i].status = DownloadStatus.queued;
    state[i].progress = 0;
    state[i].error = null;
    state = [...state];
  }

  bool has(String key) => state.any((d) => d.key == key);
  DownloadItem? byKey(String key) {
    final i = state.indexWhere((d) => d.key == key);
    return i < 0 ? null : state[i];
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadItem>>(
        (_) => DownloadNotifier());
