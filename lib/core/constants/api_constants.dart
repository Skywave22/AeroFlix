class ApiConstants {
  ApiConstants._();
  static const String tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const String tmdbApiKey = '439c478a771f35c05022f9feabcca01c';
  static const String tmdbImageBase = 'https://image.tmdb.org/t/p';
  static const String posterSizeW154 = 'w154',
      posterSizeW342 = 'w342',
      posterSizeW500 = 'w500',
      posterSizeW780 = 'w780';
  static const String backdropSizeW780 = 'w780', backdropSizeW1280 = 'w1280';
  static const String profileSizeW185 = 'w185';
  static const String defaultLanguage = 'en-US', defaultRegion = 'US';
  static const Duration connectTimeout = Duration(seconds: 12),
      receiveTimeout = Duration(seconds: 20);
  static String posterUrl(String? p, {String size = posterSizeW500}) =>
      (p == null || p.isEmpty) ? '' : '$tmdbImageBase/$size$p';
  static String backdropUrl(String? p, {String size = backdropSizeW1280}) =>
      (p == null || p.isEmpty) ? '' : '$tmdbImageBase/$size$p';
  static String profileUrl(String? p, {String size = profileSizeW185}) =>
      (p == null || p.isEmpty) ? '' : '$tmdbImageBase/$size$p';
}
