import 'package:equatable/equatable.dart';
import '../../core/constants/api_constants.dart';

enum MediaType { movie, tv }

/// Cast / crew member.
class CastMember extends Equatable {
  final int id;
  final String name, character, job;
  final String? profilePath;
  const CastMember(
      {required this.id,
      required this.name,
      this.character = '',
      this.job = '',
      this.profilePath});
  String get profileUrl => ApiConstants.profileUrl(profilePath);
  factory CastMember.fromJson(Map<String, dynamic> j, {bool isCrew = false}) =>
      CastMember(
        id: j['id'] as int? ?? 0,
        name: (j['name'] ?? '') as String,
        character: (j['character'] ?? '') as String,
        job: isCrew ? ((j['job'] ?? '') as String) : '',
        profilePath: j['profile_path'] as String?,
      );
  @override
  List<Object?> get props => [id, name];
}

class Episode extends Equatable {
  final int id, seasonNumber, episodeNumber;
  final String name, overview;
  final String? stillPath;
  final double voteAverage;
  final String? airDate;
  final int? runtime;
  const Episode(
      {required this.id,
      required this.seasonNumber,
      required this.episodeNumber,
      required this.name,
      this.overview = '',
      this.stillPath,
      this.voteAverage = 0,
      this.airDate,
      this.runtime});
  String get stillUrl =>
      ApiConstants.backdropUrl(stillPath, size: ApiConstants.backdropSizeW780);
  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: j['id'] as int? ?? 0,
        seasonNumber: (j['season_number'] as int?) ?? 1,
        episodeNumber: (j['episode_number'] as int?) ?? 0,
        name: (j['name'] ?? '') as String,
        overview: (j['overview'] ?? '') as String,
        stillPath: j['still_path'] as String?,
        voteAverage: ((j['vote_average'] as num?) ?? 0).toDouble(),
        airDate: j['air_date'] as String?,
        runtime: j['runtime'] as int?,
      );
  @override
  List<Object?> get props => [id, seasonNumber, episodeNumber];
}

class Season extends Equatable {
  final int id, seasonNumber, episodeCount;
  final String name, overview;
  final String? posterPath, airDate;
  const Season(
      {required this.id,
      required this.seasonNumber,
      required this.name,
      this.episodeCount = 0,
      this.overview = '',
      this.posterPath,
      this.airDate});
  String get posterUrl =>
      ApiConstants.posterUrl(posterPath, size: ApiConstants.posterSizeW342);
  factory Season.fromJson(Map<String, dynamic> j) => Season(
        id: j['id'] as int? ?? 0,
        seasonNumber: (j['season_number'] as int?) ?? 0,
        name: (j['name'] ?? '') as String,
        episodeCount: (j['episode_count'] as int?) ?? 0,
        overview: (j['overview'] ?? '') as String,
        posterPath: j['poster_path'] as String?,
        airDate: j['air_date'] as String?,
      );
  @override
  List<Object?> get props => [id, seasonNumber];
}

class VideoTrailer extends Equatable {
  final String id, key, name, site, type;
  final bool official;
  const VideoTrailer(
      {required this.id,
      required this.key,
      required this.name,
      required this.site,
      required this.type,
      this.official = false});
  factory VideoTrailer.fromJson(Map<String, dynamic> j) => VideoTrailer(
        id: j['id'] as String? ?? '',
        key: j['key'] as String? ?? '',
        name: (j['name'] ?? '') as String,
        site: (j['site'] ?? '') as String,
        type: (j['type'] ?? '') as String,
        official: (j['official'] as bool?) ?? false,
      );
  String get youtubeUrl => 'https://www.youtube.com/watch?v=$key';
  @override
  List<Object?> get props => [id, key];
}

/// Aggregated detail view for a title (movie or tv).
class MediaDetails extends Equatable {
  final MediaType type;
  final int id;
  final String title;
  final String? tagline,
      overview,
      posterPath,
      backdropPath,
      releaseDate,
      status,
      originalLanguage;
  final double voteAverage;
  final int voteCount, runtime;
  final List<int> genreIds;
  final List<String> genreNames;
  final List<CastMember> cast;
  final List<VideoTrailer> trailers;
  final List<Season> seasons; // empty for movies
  final int numberOfSeasons;
  const MediaDetails({
    required this.type,
    required this.id,
    required this.title,
    this.tagline,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.status,
    this.originalLanguage,
    this.voteAverage = 0,
    this.voteCount = 0,
    this.runtime = 0,
    this.genreIds = const [],
    this.genreNames = const [],
    this.cast = const [],
    this.trailers = const [],
    this.seasons = const [],
    this.numberOfSeasons = 0,
  });

  String get posterUrlW500 => ApiConstants.posterUrl(posterPath);
  String get backdropUrlW1280 => ApiConstants.backdropUrl(backdropPath);
  String? get year => (releaseDate != null && releaseDate!.length >= 4)
      ? releaseDate!.substring(0, 4)
      : null;
  String get rating => voteAverage > 0 ? voteAverage.toStringAsFixed(1) : '—';
  String get runtimeLabel {
    if (runtime <= 0) return '';
    final h = runtime ~/ 60, m = runtime % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  List<Object?> get props => [id, type];
}
