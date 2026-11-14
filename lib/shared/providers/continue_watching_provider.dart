import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../models/media_details.dart';

/// A resume point: enough info to reopen a title at a specific position and
/// (for TV) a specific episode.
class ContinueWatchingItem {
  final MediaType type;
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final int season; // 0 for movies
  final int episode; // 0 for movies
  final String? episodeTitle;
  final int positionMs;
  final int durationMs;
  final int updatedAt; // epoch millis

  const ContinueWatchingItem({
    required this.type,
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    this.season = 0,
    this.episode = 0,
    this.episodeTitle,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  bool get isFinished => durationMs > 0 && positionMs >= durationMs - 30000;

  String get key => _keyFor(type, id, season, episode);

  static String _keyFor(MediaType t, int id, int s, int e) =>
      '${t.name}:$id:${s}x${e.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'id': id,
        'title': title,
        'posterPath': posterPath,
        'backdropPath': backdropPath,
        'season': season,
        'episode': episode,
        'episodeTitle': episodeTitle,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt,
      };

  factory ContinueWatchingItem.fromJson(Map<String, dynamic> j) =>
      ContinueWatchingItem(
        type: MediaType.values.firstWhere((t) => t.name == j['type'],
            orElse: () => MediaType.movie),
        id: (j['id'] as int?) ?? 0,
        title: (j['title'] ?? '') as String,
        posterPath: j['posterPath'] as String?,
        backdropPath: j['backdropPath'] as String?,
        season: (j['season'] as int?) ?? 0,
        episode: (j['episode'] as int?) ?? 0,
        episodeTitle: j['episodeTitle'] as String?,
        positionMs: (j['positionMs'] as int?) ?? 0,
        durationMs: (j['durationMs'] as int?) ?? 0,
        updatedAt: (j['updatedAt'] as int?) ?? 0,
      );

  ContinueWatchingItem copyWith({
    int? positionMs,
    int? durationMs,
    int? updatedAt,
    String? episodeTitle,
    String? posterPath,
    String? backdropPath,
  }) =>
      ContinueWatchingItem(
        type: type,
        id: id,
        title: title,
        posterPath: posterPath ?? this.posterPath,
        backdropPath: backdropPath ?? this.backdropPath,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle ?? this.episodeTitle,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ContinueWatchingNotifier
    extends StateNotifier<List<ContinueWatchingItem>> {
  ContinueWatchingNotifier() : super(const []) {
    _load();
  }

  static const _key = AppConstants.prefContinueWatching;
  bool _loaded = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      state = const [];
    } else {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final items = list.map(ContinueWatchingItem.fromJson).toList();
        items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        state = items;
      } catch (_) {
        state = const [];
      }
    }
    _loaded = true;
  }

  Future<void> _save() async {
    if (!_loaded) await _load();
    final prefs = await SharedPreferences.getInstance();
    // Cap at 24 entries
    final list = state.take(24).map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }

  ContinueWatchingItem? findFor(MediaType t, int id,
      {int season = 0, int episode = 0}) {
    final k = ContinueWatchingItem._keyFor(t, id, season, episode);
    for (final i in state) {
      if (i.key == k) return i;
    }
    return null;
  }

  Future<void> saveProgress({
    required MediaType type,
    required int id,
    required String title,
    String? posterPath,
    String? backdropPath,
    int season = 0,
    int episode = 0,
    String? episodeTitle,
    required int positionMs,
    required int durationMs,
  }) async {
    final k = ContinueWatchingItem._keyFor(type, id, season, episode);
    final existingIdx = state.indexWhere((i) => i.key == k);
    final now = DateTime.now().millisecondsSinceEpoch;

    ContinueWatchingItem item;
    if (existingIdx >= 0) {
      item = state[existingIdx].copyWith(
        positionMs: positionMs,
        durationMs: durationMs,
        updatedAt: now,
        episodeTitle: episodeTitle,
        posterPath: posterPath,
        backdropPath: backdropPath,
      );
    } else {
      item = ContinueWatchingItem(
        type: type,
        id: id,
        title: title,
        posterPath: posterPath,
        backdropPath: backdropPath,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
        positionMs: positionMs,
        durationMs: durationMs,
        updatedAt: now,
      );
    }

    // If finished (>95%), remove from the list
    var next = [...state];
    if (existingIdx >= 0) next.removeAt(existingIdx);
    if (!item.isFinished) {
      next.insert(0, item);
    }
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = next.take(24).toList();
    await _save();
  }

  Future<void> remove(MediaType t, int id,
      {int season = 0, int episode = 0}) async {
    final k = ContinueWatchingItem._keyFor(t, id, season, episode);
    state = state.where((i) => i.key != k).toList();
    await _save();
  }

  Future<void> clear() async {
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final continueWatchingProvider =
    StateNotifierProvider<ContinueWatchingNotifier, List<ContinueWatchingItem>>(
        (ref) => ContinueWatchingNotifier());
