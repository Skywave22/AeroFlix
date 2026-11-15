import 'package:equatable/equatable.dart';

/// One legal place to watch a title, from TMDB's Watch Providers
/// (data © JustWatch). `logoPath` is a TMDB relative image path.
class WatchProvider extends Equatable {
  final int providerId;
  final String displayName;
  final String? logoPath;
  const WatchProvider({
    required this.providerId,
    required this.displayName,
    this.logoPath,
  });

  String get logoUrl =>
      logoPath == null ? '' : 'https://image.tmdb.org/t/p/w92$logoPath';

  factory WatchProvider.fromJson(Map<String, dynamic> j) => WatchProvider(
        providerId: (j['provider_id'] as int?) ?? 0,
        displayName: (j['provider_name'] ?? '') as String,
        logoPath: j['logo_path'] as String?,
      );

  @override
  List<Object?> get props => [providerId];
}

/// Watch options for one region: subscription / rent / buy rows plus the
/// JustWatch partner link for the title in that region.
class WatchProviders extends Equatable {
  final String region;
  final List<WatchProvider> flatrate; // subscription streaming
  final List<WatchProvider> rent;
  final List<WatchProvider> buy;
  final String? link; // JustWatch page for the title

  const WatchProviders({
    required this.region,
    this.flatrate = const [],
    this.rent = const [],
    this.buy = const [],
    this.link,
  });

  bool get isEmpty => flatrate.isEmpty && rent.isEmpty && buy.isEmpty;

  @override
  List<Object?> get props => [region, flatrate, rent, buy, link];
}
