import 'package:equatable/equatable.dart';

import '../../core/constants/api_constants.dart';
import 'movie.dart';
import 'tv_show.dart';

class PersonSearchResult extends Equatable {
  final int id;
  final String name;
  final String? profilePath;
  final String? knownForDepartment;
  final List<Movie> knownForMovies;
  final List<TvShow> knownForTv;
  const PersonSearchResult({
    required this.id,
    required this.name,
    this.profilePath,
    this.knownForDepartment,
    this.knownForMovies = const [],
    this.knownForTv = const [],
  });
  String get profileUrl =>
      ApiConstants.profileUrl(profilePath, size: ApiConstants.profileSizeW185);
  String knownForLabel() {
    final all = <String>[
      ...knownForMovies.map((m) => m.title),
      ...knownForTv.map((t) => t.name),
    ].where((s) => s.isNotEmpty).take(3).toList();
    if (all.isEmpty) return knownForDepartment ?? '';
    return all.join(', ');
  }

  @override
  List<Object?> get props => [id];
}
