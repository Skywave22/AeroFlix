import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../errors/failures.dart';
import '../../shared/models/genre.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/movie.dart';
import '../../shared/models/person.dart';
import '../../shared/models/tv_show.dart';
import 'dio_client.dart';

class TmdbService {
  TmdbService(this._dio);
  final Dio _dio;

  Future<List<Movie>> getTrendingMovies({String tw = 'week'}) =>
      _fetchMovies('/trending/movie/$tw');
  Future<List<TvShow>> getTrendingTv({String tw = 'week'}) =>
      _fetchTv('/trending/tv/$tw');
  Future<List<Movie>> getPopularMovies() => _fetchMovies('/movie/popular');
  Future<List<Movie>> getTopRatedMovies() => _fetchMovies('/movie/top_rated');
  Future<List<Movie>> getNowPlayingMovies() =>
      _fetchMovies('/movie/now_playing');
  Future<List<TvShow>> getPopularTv() => _fetchTv('/tv/popular');
  Future<List<TvShow>> getTopRatedTv() => _fetchTv('/tv/top_rated');
  Future<List<Movie>> getHindiMovies() => _fetchMovies('/discover/movie',
      query: {'with_original_language': 'hi', 'sort_by': 'popularity.desc'});
  Future<List<Movie>> getMoviesByGenre(int genreId) =>
      _fetchMovies('/discover/movie',
          query: {'with_genres': '$genreId', 'sort_by': 'popularity.desc'});
  Future<List<TvShow>> getTvByGenre(int genreId) => _fetchTv('/discover/tv',
      query: {'with_genres': '$genreId', 'sort_by': 'popularity.desc'});

  Future<List<Genre>> getMovieGenres() async {
    final r = await _get('/genre/movie/list');
    return (r['genres'] as List)
        .cast<Map<String, dynamic>>()
        .map(Genre.fromJson)
        .toList();
  }

  Future<MediaDetails> getMovieDetails(int id) async {
    final r = await _get('/movie/$id',
        extraQuery: {'append_to_response': 'credits,videos,similar'});
    return _parseMovie(r);
  }

  Future<MediaDetails> getTvDetails(int id) async {
    final r = await _get('/tv/$id',
        extraQuery: {'append_to_response': 'credits,videos,similar'});
    return _parseTv(r);
  }

  Future<List<Episode>> getEpisodes(int tvId, int seasonNumber) async {
    final r = await _get('/tv/$tvId/season/$seasonNumber');
    return (r['episodes'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(Episode.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> _fetchPersonCredits(int id) =>
      _get('/person/$id/combined_credits');

  Future<PersonInfo> getPersonInfo(int id) async {
    final r = await _get('/person/$id');
    return PersonInfo.fromJson(r);
  }

  Future<PersonCredits> getPersonCredits(int id) async {
    final r = await _fetchPersonCredits(id);
    final movies = <Movie>[];
    final tv = <TvShow>[];
    for (final x
        in (r['cast'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final mediaType = x['media_type'] as String?;
      if (mediaType == 'movie' && (x['poster_path'] != null)) {
        movies.add(Movie.fromJson(x));
      } else if (mediaType == 'tv' && (x['poster_path'] != null)) {
        tv.add(TvShow.fromJson(x));
      }
    }
    movies.sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
    tv.sort((a, b) => (b.firstAirDate ?? '').compareTo(a.firstAirDate ?? ''));
    return PersonCredits(
        movies: movies.take(20).toList(), tv: tv.take(20).toList());
  }

  Future<Map<String, dynamic>> searchMulti(String q, {int page = 1}) async {
    if (q.trim().isEmpty) return {'movies': <Movie>[], 'tv': <TvShow>[]};
    final r = await _get('/search/multi',
        extraQuery: {'query': q, 'page': '$page', 'include_adult': 'false'});
    final results = (r['results'] as List).cast<Map<String, dynamic>>();
    final movies = <Movie>[], tv = <TvShow>[];
    for (final x in results) {
      if (x['media_type'] == 'movie') {
        movies.add(Movie.fromJson(x));
      } else if (x['media_type'] == 'tv') {
        tv.add(TvShow.fromJson(x));
      }
    }
    return {
      'movies': movies,
      'tv': tv,
      'page': r['page'] as int? ?? 1,
      'totalPages': r['total_pages'] as int? ?? 1
    };
  }

  Future<List<Movie>> _fetchMovies(String p,
      {Map<String, String>? query}) async {
    final r = await _get(p, extraQuery: query);
    return (r['results'] as List)
        .cast<Map<String, dynamic>>()
        .map(Movie.fromJson)
        .toList();
  }

  Future<List<TvShow>> _fetchTv(String p, {Map<String, String>? query}) async {
    final r = await _get(p, extraQuery: query);
    return (r['results'] as List)
        .cast<Map<String, dynamic>>()
        .map(TvShow.fromJson)
        .toList();
  }

  MediaDetails _parseMovie(Map<String, dynamic> r) {
    final genres = (r['genres'] as List? ?? []).cast<Map<String, dynamic>>();
    final credits = r['credits'] as Map<String, dynamic>? ?? {};
    final videos =
        ((r['videos'] as Map<String, dynamic>? ?? {})['results'] as List? ?? [])
            .cast<Map<String, dynamic>>();
    return MediaDetails(
      type: MediaType.movie,
      id: r['id'] as int,
      title: (r['title'] ?? '') as String,
      tagline: r['tagline'] as String?,
      overview: r['overview'] as String?,
      posterPath: r['poster_path'] as String?,
      backdropPath: r['backdrop_path'] as String?,
      releaseDate: r['release_date'] as String?,
      status: r['status'] as String?,
      originalLanguage: r['original_language'] as String?,
      voteAverage: ((r['vote_average'] as num?) ?? 0).toDouble(),
      voteCount: (r['vote_count'] as int?) ?? 0,
      runtime: (r['runtime'] as int?) ?? 0,
      genreIds: genres.map((g) => g['id'] as int).toList(),
      genreNames: genres.map((g) => (g['name'] ?? '') as String).toList(),
      cast: (credits['cast'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .take(12)
          .map(CastMember.fromJson)
          .toList(),
      trailers: videos
          .where((v) => v['type'] == 'Trailer' && v['site'] == 'YouTube')
          .map(VideoTrailer.fromJson)
          .take(1)
          .toList(),
      similar: _parseSimilar(r, MediaType.movie),
    );
  }

  List<SimilarTitle> _parseSimilar(Map<String, dynamic> r, MediaType type) {
    final sim = r['similar'] as Map<String, dynamic>? ?? {};
    final results = (sim['results'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((m) => (m['poster_path'] as String?) != null)
        .take(18)
        .map((m) => SimilarTitle.fromJson(m, type))
        .toList();
    return results;
  }

  MediaDetails _parseTv(Map<String, dynamic> r) {
    final genres = (r['genres'] as List? ?? []).cast<Map<String, dynamic>>();
    final credits = r['credits'] as Map<String, dynamic>? ?? {};
    final videos =
        ((r['videos'] as Map<String, dynamic>? ?? {})['results'] as List? ?? [])
            .cast<Map<String, dynamic>>();
    final rawSeasons =
        (r['seasons'] as List? ?? []).cast<Map<String, dynamic>>();
    final seasons = rawSeasons
        .where((s) => (s['season_number'] as int? ?? 0) > 0)
        .map(Season.fromJson)
        .toList();
    final epRuntime = (r['episode_run_time'] as List? ?? []);
    return MediaDetails(
      type: MediaType.tv,
      id: r['id'] as int,
      title: (r['name'] ?? '') as String,
      tagline: r['tagline'] as String?,
      overview: r['overview'] as String?,
      posterPath: r['poster_path'] as String?,
      backdropPath: r['backdrop_path'] as String?,
      releaseDate: r['first_air_date'] as String?,
      status: r['status'] as String?,
      originalLanguage: r['original_language'] as String?,
      voteAverage: ((r['vote_average'] as num?) ?? 0).toDouble(),
      voteCount: (r['vote_count'] as int?) ?? 0,
      runtime: epRuntime.isNotEmpty ? (epRuntime.first as int? ?? 0) : 0,
      genreIds: genres.map((g) => g['id'] as int).toList(),
      genreNames: genres.map((g) => (g['name'] ?? '') as String).toList(),
      cast: (credits['cast'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .take(12)
          .map(CastMember.fromJson)
          .toList(),
      trailers: videos
          .where((v) => v['type'] == 'Trailer' && v['site'] == 'YouTube')
          .map(VideoTrailer.fromJson)
          .take(1)
          .toList(),
      seasons: seasons,
      numberOfSeasons: (r['number_of_seasons'] as int?) ?? seasons.length,
      similar: _parseSimilar(r, MediaType.tv),
    );
  }

  Future<Map<String, dynamic>> _get(String path,
      {Map<String, String>? extraQuery}) async {
    try {
      final r = await _dio.get(path, queryParameters: extraQuery);
      if (r.statusCode == 404) throw Failure.notFound();
      if (r.statusCode == null || r.statusCode! < 200 || r.statusCode! >= 300) {
        throw Failure.server(message: 'HTTP ${r.statusCode}');
      }
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if ({
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout
      }.contains(e.type)) {
        throw Failure.timeout(cause: e);
      }
      if (e.type == DioExceptionType.connectionError) {
        throw Failure.network(cause: e);
      }
      if (e.response?.statusCode == 404) {
        throw Failure.notFound();
      }
      throw Failure.server(cause: e);
    } catch (e) {
      if (e is Failure) rethrow;
      throw Failure.parse(cause: e);
    }
  }
}

final tmdbServiceProvider =
    Provider<TmdbService>((ref) => TmdbService(ref.watch(dioProvider)));
final trendingMoviesProvider = FutureProvider<List<Movie>>(
    (ref) => ref.watch(tmdbServiceProvider).getTrendingMovies());
final trendingTvProvider = FutureProvider<List<TvShow>>(
    (ref) => ref.watch(tmdbServiceProvider).getTrendingTv());
final popularMoviesProvider = FutureProvider<List<Movie>>(
    (ref) => ref.watch(tmdbServiceProvider).getPopularMovies());
final popularTvProvider = FutureProvider<List<TvShow>>(
    (ref) => ref.watch(tmdbServiceProvider).getPopularTv());
final topRatedMoviesProvider = FutureProvider<List<Movie>>(
    (ref) => ref.watch(tmdbServiceProvider).getTopRatedMovies());
final nowPlayingMoviesProvider = FutureProvider<List<Movie>>(
    (ref) => ref.watch(tmdbServiceProvider).getNowPlayingMovies());
final hindiMoviesProvider = FutureProvider<List<Movie>>(
    (ref) => ref.watch(tmdbServiceProvider).getHindiMovies());
final movieGenresProvider = FutureProvider<List<Genre>>(
    (ref) => ref.watch(tmdbServiceProvider).getMovieGenres());
