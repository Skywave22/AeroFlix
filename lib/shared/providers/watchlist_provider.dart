import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../models/media_details.dart';
import '../models/movie.dart';
import '../models/tv_show.dart';

/// Watchlist stored locally as a set of TMDB IDs keyed by media type
/// ("movie:12345" / "tv:67890"). V1 is local-only; cloud sync lands
/// when auth is added.
class WatchlistNotifier extends StateNotifier<Set<String>> {
  WatchlistNotifier() : super(const {}) {
    _load();
  }

  static const _key = AppConstants.prefWatchlist;
  bool _loaded = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_key)?.toSet() ?? const {};
    _loaded = true;
  }

  Future<void> _save() async {
    if (!_loaded) await _load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state.toList());
  }

  bool isWatched(MediaType type, int id) => state.contains('${type.name}:$id');
  bool isMovieWatched(int id) => state.contains('movie:$id');
  bool isTvWatched(int id) => state.contains('tv:$id');

  Future<void> toggle(MediaType type, int id) async {
    final key = '${type.name}:$id';
    if (state.contains(key)) {
      state = {...state}..remove(key);
    } else {
      state = {...state, key};
    }
    await _save();
  }

  Future<void> toggleMovie(Movie m) => toggle(MediaType.movie, m.id);
  Future<void> toggleTv(TvShow s) => toggle(MediaType.tv, s.id);
}

final watchlistProvider =
    StateNotifierProvider<WatchlistNotifier, Set<String>>((ref) {
  return WatchlistNotifier();
});

final isInWatchlistProvider = Provider.family<bool, String>((ref, key) {
  final wl = ref.watch(watchlistProvider);
  return wl.contains(key);
});
