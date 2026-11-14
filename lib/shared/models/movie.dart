import 'package:equatable/equatable.dart';
import '../../core/constants/api_constants.dart';

class Movie extends Equatable {
  final int id;
  final String title;
  final String? posterPath,
      backdropPath,
      overview,
      releaseDate,
      originalLanguage;
  final double voteAverage, popularity;
  final int voteCount;
  final List<int> genreIds;
  final bool adult;
  const Movie(
      {required this.id,
      required this.title,
      this.posterPath,
      this.backdropPath,
      this.overview = '',
      this.voteAverage = 0,
      this.voteCount = 0,
      this.releaseDate,
      this.genreIds = const [],
      this.popularity = 0,
      this.adult = false,
      this.originalLanguage});
  String get posterUrlW500 => ApiConstants.posterUrl(posterPath);
  String get posterUrlW342 =>
      ApiConstants.posterUrl(posterPath, size: ApiConstants.posterSizeW342);
  String get backdropUrlW1280 => ApiConstants.backdropUrl(backdropPath);
  String get backdropUrlW780 => ApiConstants.backdropUrl(backdropPath,
      size: ApiConstants.backdropSizeW780);
  String? get year => (releaseDate != null && releaseDate!.length >= 4)
      ? releaseDate!.substring(0, 4)
      : null;
  String get rating => voteAverage > 0 ? voteAverage.toStringAsFixed(1) : '—';
  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
        id: j['id'] as int,
        title: (j['title'] ?? j['name'] ?? '') as String,
        posterPath: j['poster_path'] as String?,
        backdropPath: j['backdrop_path'] as String?,
        overview: (j['overview'] ?? '') as String,
        voteAverage: ((j['vote_average'] as num?) ?? 0).toDouble(),
        voteCount: (j['vote_count'] as int?) ?? 0,
        releaseDate: j['release_date'] as String?,
        genreIds: (j['genre_ids'] as List<dynamic>?)?.cast<int>() ?? const [],
        popularity: ((j['popularity'] as num?) ?? 0).toDouble(),
        adult: (j['adult'] as bool?) ?? false,
        originalLanguage: j['original_language'] as String?,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'overview': overview,
        'vote_average': voteAverage,
        'vote_count': voteCount,
        'release_date': releaseDate,
        'genre_ids': genreIds,
        'popularity': popularity,
        'adult': adult,
        'original_language': originalLanguage
      };
  @override
  List<Object?> get props => [id, title];
}
