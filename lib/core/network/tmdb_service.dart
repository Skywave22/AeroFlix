import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../errors/failures.dart';
import '../../shared/models/genre.dart';
import '../../shared/models/movie.dart';
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

  Future<List<Genre>> getMovieGenres() async {
    final r = await _get('/genre/movie/list');
    return (r['genres'] as List)
        .cast<Map<String, dynamic>>()
        .map(Genre.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> getMovieDetails(int id) => _get('/movie/$id',
      extraQuery: {'append_to_response': 'credits,videos,similar'});
  Future<Map<String, dynamic>> getTvDetails(int id) => _get('/tv/$id',
      extraQuery: {'append_to_response': 'credits,videos,similar'});
  Future<Map<String, dynamic>> getTvSeason(int id, int s) =>
      _get('/tv/$id/season/$s');

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
        DioExceptionType.sendTimeout,
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
      if (e is Failure) {
        rethrow;
      }
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
