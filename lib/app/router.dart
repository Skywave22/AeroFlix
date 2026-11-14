import 'package:go_router/go_router.dart';
import '../features/explore/explore_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../features/watchlist/watchlist_screen.dart';
import 'app_shell.dart';

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
]);
