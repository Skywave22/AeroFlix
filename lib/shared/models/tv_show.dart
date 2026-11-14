import 'package:equatable/equatable.dart';
import '../../core/constants/api_constants.dart';

class TvShow extends Equatable {
  final int id;
  final String name;
  final String? posterPath, backdropPath, overview, firstAirDate;
  final double voteAverage, popularity;
  final int voteCount, numberOfSeasons;
  final List<int> genreIds;
  const TvShow(
      {required this.id,
      required this.name,
      this.posterPath,
      this.backdropPath,
      this.overview = '',
      this.voteAverage = 0,
      this.voteCount = 0,
      this.firstAirDate,
      this.genreIds = const [],
      this.popularity = 0,
      this.numberOfSeasons = 0});
  String get posterUrlW500 => ApiConstants.posterUrl(posterPath);
  String get posterUrlW342 =>
      ApiConstants.posterUrl(posterPath, size: ApiConstants.posterSizeW342);
  String get backdropUrlW1280 => ApiConstants.backdropUrl(backdropPath);
  String? get year => (firstAirDate != null && firstAirDate!.length >= 4)
      ? firstAirDate!.substring(0, 4)
      : null;
  String get rating => voteAverage > 0 ? voteAverage.toStringAsFixed(1) : '—';
  factory TvShow.fromJson(Map<String, dynamic> j) => TvShow(
        id: j['id'] as int,
        name: (j['name'] ?? j['title'] ?? '') as String,
        posterPath: j['poster_path'] as String?,
        backdropPath: j['backdrop_path'] as String?,
        overview: (j['overview'] ?? '') as String,
        voteAverage: ((j['vote_average'] as num?) ?? 0).toDouble(),
        voteCount: (j['vote_count'] as int?) ?? 0,
        firstAirDate: j['first_air_date'] as String?,
        genreIds: (j['genre_ids'] as List<dynamic>?)?.cast<int>() ?? const [],
        popularity: ((j['popularity'] as num?) ?? 0).toDouble(),
        numberOfSeasons: (j['number_of_seasons'] as int?) ?? 0,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'overview': overview,
        'vote_average': voteAverage,
        'vote_count': voteCount,
        'first_air_date': firstAirDate,
        'genre_ids': genreIds,
        'popularity': popularity,
        'number_of_seasons': numberOfSeasons
      };
  @override
  List<Object?> get props => [id, name];
}
