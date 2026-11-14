import 'package:go_router/go_router.dart';
import '../shared/models/media_details.dart';
import '../features/details/details_screen.dart';
import '../features/episodes/episodes_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/home/home_screen.dart';
import '../features/player/player_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../features/watchlist/watchlist_screen.dart';
import 'app_shell.dart';

/// Arguments pushed to the episodes route via GoRouter `extra`.
class EpisodesArgs {
  final MediaDetails details;
  final int initialSeason;
  const EpisodesArgs({required this.details, required this.initialSeason});
}

/// Arguments pushed to the player route via GoRouter `extra`.
class PlayerArgs {
  final MediaDetails details;
  final int season;
  final int episode;
  final String? episodeTitle;
  final int resumeAtMs;
  final PlayerArgs? nextEpisode;
  const PlayerArgs({
    required this.details,
    this.season = 0,
    this.episode = 0,
    this.episodeTitle,
    this.resumeAtMs = 0,
    this.nextEpisode,
  });
}

final appRouter =
    GoRouter(initialLocation: '/home', debugLogDiagnostics: false, routes: [
  StatefulShellRoute.indexedStack(
      builder: (c, s, shell) => AppShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (c, s) => const HomeScreen())
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/explore', builder: (c, s) => const ExploreScreen())
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/search', builder: (c, s) => const SearchScreen())
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/watchlist', builder: (c, s) => const WatchlistScreen())
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen())
        ]),
      ]),
  GoRoute(
      path: '/details/movie/:id',
      builder: (c, s) {
        final id = int.parse(s.pathParameters['id']!);
        final poster = s.uri.queryParameters['poster'];
        return DetailsScreen(
            args:
                DetailsArgs(id: id, type: MediaType.movie, posterUrl: poster));
      }),
  GoRoute(
      path: '/details/tv/:id',
      builder: (c, s) {
        final id = int.parse(s.pathParameters['id']!);
        final poster = s.uri.queryParameters['poster'];
        return DetailsScreen(
            args: DetailsArgs(id: id, type: MediaType.tv, posterUrl: poster));
      }),
  GoRoute(
      path: '/player',
      builder: (c, s) {
        final args = s.extra as PlayerArgs;
        return PlayerScreen(
            details: args.details,
            season: args.season,
            episode: args.episode,
            episodeTitle: args.episodeTitle);
      }),
  GoRoute(
      path: '/episodes',
      builder: (c, s) {
        final args = s.extra as EpisodesArgs;
        return EpisodesScreen(
            details: args.details, initialSeason: args.initialSeason);
      }),
]);
