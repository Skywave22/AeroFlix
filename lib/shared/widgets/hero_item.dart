import '../../core/constants/api_constants.dart';
import '../models/movie.dart';
import '../models/tv_show.dart';

/// Unified hero item so the rotating banner can mix movies + TV.
class HeroItem {
  final int id;
  final String kind; // 'movie' | 'tv'
  final String title;
  final String? backdropPath;
  final String? posterPath;
  final String? overview;
  final String? releaseDate;
  final double voteAverage;
  final List<int> genreIds;
  const HeroItem({
    required this.id,
    required this.kind,
    required this.title,
    this.backdropPath,
    this.posterPath,
    this.overview,
    this.releaseDate,
    this.voteAverage = 0,
    this.genreIds = const [],
  });

  String get backdropUrl => ApiConstants.backdropUrl(backdropPath,
      size: ApiConstants.backdropSizeW1280);
  String get posterUrl =>
      ApiConstants.posterUrl(posterPath, size: ApiConstants.posterSizeW342);
  String get year => (releaseDate != null && releaseDate!.length >= 4)
      ? releaseDate!.substring(0, 4)
      : '';

  factory HeroItem.fromMovie(Movie m) => HeroItem(
        id: m.id,
        kind: 'movie',
        title: m.title,
        backdropPath: m.backdropPath,
        posterPath: m.posterPath,
        overview: m.overview,
        releaseDate: m.releaseDate,
        voteAverage: m.voteAverage,
        genreIds: m.genreIds,
      );

  factory HeroItem.fromTv(TvShow s) => HeroItem(
        id: s.id,
        kind: 'tv',
        title: s.name,
        backdropPath: s.backdropPath,
        posterPath: s.posterPath,
        overview: s.overview,
        releaseDate: s.firstAirDate,
        voteAverage: s.voteAverage,
        genreIds: s.genreIds,
      );
}
