import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/models/media_details.dart';
import '../features/details/details_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/episodes/episodes_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/home/home_screen.dart';
import '../features/person/person_screen.dart';
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

  /// When set, the player opens this local file (a completed download)
  /// instead of resolving an online stream.
  final String? localFilePath;
  const PlayerArgs({
    required this.details,
    this.season = 0,
    this.episode = 0,
    this.episodeTitle,
    this.resumeAtMs = 0,
    this.nextEpisode,
    this.localFilePath,
  });
}

/// Shown when a route is reached without valid navigation arguments
/// (e.g. after a hot restart, since `extra` is not persisted).
class _RouteFallback extends StatelessWidget {
  final String message;
  const _RouteFallback({required this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.movie_filter_outlined, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('Go home'),
              ),
            ]),
          ),
        ),
      );
}

int? _parseId(String? raw) => raw == null ? null : int.tryParse(raw);

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
        final id = _parseId(s.pathParameters['id']);
        if (id == null) {
          return const _RouteFallback(message: 'That title link is invalid.');
        }
        final poster = s.uri.queryParameters['poster'];
        return DetailsScreen(
            args:
                DetailsArgs(id: id, type: MediaType.movie, posterUrl: poster));
      }),
  GoRoute(
      path: '/details/tv/:id',
      builder: (c, s) {
        final id = _parseId(s.pathParameters['id']);
        if (id == null) {
          return const _RouteFallback(message: 'That title link is invalid.');
        }
        final poster = s.uri.queryParameters['poster'];
        return DetailsScreen(
            args: DetailsArgs(id: id, type: MediaType.tv, posterUrl: poster));
      }),
  GoRoute(path: '/downloads', builder: (c, s) => const DownloadsScreen()),
  GoRoute(
      path: '/player',
      builder: (c, s) {
        final args = s.extra;
        if (args is! PlayerArgs) {
          return const _RouteFallback(
              message: 'This player session expired. Pick the title again.');
        }
        return PlayerScreen(
            details: args.details,
            season: args.season,
            episode: args.episode,
            episodeTitle: args.episodeTitle,
            resumeAtMs: args.resumeAtMs,
            nextEpisode: args.nextEpisode,
            localFilePath: args.localFilePath);
      }),
  GoRoute(
      path: '/episodes',
      builder: (c, s) {
        final args = s.extra;
        if (args is! EpisodesArgs) {
          return const _RouteFallback(
              message: 'That episode list could not be opened.');
        }
        return EpisodesScreen(
            details: args.details, initialSeason: args.initialSeason);
      }),
  GoRoute(
      path: '/person/:id',
      builder: (c, s) {
        final id = _parseId(s.pathParameters['id']);
        if (id == null) {
          return const _RouteFallback(message: 'That person link is invalid.');
        }
        final name = s.uri.queryParameters['name'] ?? '';
        final profile = s.uri.queryParameters['profile'];
        return PersonScreen(
            args: PersonArgs(id: id, name: name, profilePath: profile));
      }),
]);
