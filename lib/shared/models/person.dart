import 'package:equatable/equatable.dart';
import 'movie.dart';
import 'tv_show.dart';

class PersonInfo extends Equatable {
  final int id;
  final String name, biography;
  final String? profilePath, birthday, deathday, placeOfBirth;
  final double popularity;
  const PersonInfo({
    required this.id,
    required this.name,
    this.biography = '',
    this.profilePath,
    this.birthday,
    this.deathday,
    this.placeOfBirth,
    this.popularity = 0,
  });
  factory PersonInfo.fromJson(Map<String, dynamic> j) => PersonInfo(
        id: (j['id'] as int?) ?? 0,
        name: (j['name'] ?? '') as String,
        biography: (j['biography'] ?? '') as String,
        profilePath: j['profile_path'] as String?,
        birthday: j['birthday'] as String?,
        deathday: j['deathday'] as String?,
        placeOfBirth: j['place_of_birth'] as String?,
        popularity: ((j['popularity'] as num?) ?? 0).toDouble(),
      );
  @override
  List<Object?> get props => [id];
}

class PersonCredits {
  final List<Movie> movies;
  final List<TvShow> tv;
  const PersonCredits({this.movies = const [], this.tv = const []});
}
