import 'package:aeroflix/app/router.dart';
import 'package:aeroflix/app/theme/app_colors.dart';
import 'package:aeroflix/app/theme/app_theme.dart';
import 'package:aeroflix/shared/models/movie.dart';
import 'package:aeroflix/shared/models/tv_show.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// App-level tests.
///
/// The previous version of this file pumped a hand-written `MaterialApp` with
/// `Text('AeroFlix')` in it and asserted that the text existed. That cannot
/// fail: it never touched the real theme, the real router or a single model,
/// so it was a green light that meant nothing. These tests exercise the things
/// every screen depends on.
void main() {
  group('routing table', () {
    test('declares every deep-linkable route the app links to', () {
      // The router is the single source of truth for navigation. A missing or
      // renamed path breaks every `context.push`/`go` that targets it, and the
      // failure only shows up at runtime on a device.
      final paths = appRouter.configuration.routes.expand(_allPaths).toSet();

      expect(
        paths,
        containsAll(<String>[
          '/home',
          '/explore',
          '/search',
          '/watchlist',
          '/profile',
          '/details/movie/:id',
          '/details/tv/:id',
          '/episodes',
          '/player',
        ]),
      );
    });

    test('the five tabs are all shell branches, so their state is preserved', () {
      final shell = appRouter.configuration.routes
          .whereType<StatefulShellRoute>()
          .single;
      expect(shell.branches, hasLength(5));
    });
  });

  group('theme', () {
    test('is a dark Material 3 theme with readable text on every surface', () {
      final theme = AppTheme.dark();

      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.background);

      // Body text has to stay legible on each background the app actually
      // paints. TextMuted is deliberately dimmer and is only ever used for
      // secondary/meta lines, so it is held to the 3:1 non-text bar.
      for (final background in <Color>[
        AppColors.background,
        AppColors.surface,
        AppColors.surfaceElevated,
      ]) {
        expect(
          _contrastRatio(AppColors.textPrimary, background),
          greaterThanOrEqualTo(4.5),
          reason: 'primary text on $background',
        );
        expect(
          _contrastRatio(AppColors.textMuted, background),
          greaterThanOrEqualTo(3.0),
          reason: 'muted text on $background',
        );
      }
    });

    test('paints app bars and sheets with the brand radii, not defaults', () {
      final theme = AppTheme.dark();
      // A zero-radius default is how the pre-1.4 builds looked: square sheets
      // cut into the rounded hero card above them.
      final sheetRadius = theme.bottomSheetTheme.shape;
      expect(sheetRadius, isNotNull);
      expect(
        (theme.bottomSheetTheme.shape! as RoundedRectangleBorder)
            .borderRadius
            .topLeft
            .x,
        greaterThan(0),
      );
    });
  });

  group('model parsing tolerates real TMDB payloads', () {
    test('Movie survives missing and null fields', () {
      final movie = Movie.fromJson(<String, dynamic>{
        'id': 1,
        'title': 'Dune',
        'poster_path': null,
        'overview': null,
        'vote_average': 8,
        'genre_ids': <dynamic>[28, 12],
      });

      expect(movie.title, 'Dune');
      expect(movie.posterPath, isNull);
      expect(movie.voteAverage, 8.0);
      expect(movie.genreIds, <int>[28, 12]);
      // TMDB omits poster_path/release_date for some titles. The helpers must
      // degrade to an empty URL (a placeholder) rather than '$null' or a crash.
      expect(movie.posterUrlW342, isEmpty);
      expect(movie.year, isNull);
    });

    test('TvShow falls back to name and first_air_date', () {
      final show = TvShow.fromJson(<String, dynamic>{
        'id': 1396,
        'name': 'Breaking Bad',
        'first_air_date': '2008-01-20',
        'vote_average': 9,
      });

      expect(show.name, 'Breaking Bad');
      expect(show.year, '2008');
    });
  });
}

/// Flattens a route tree, including the branches of a stateful shell.
Iterable<String> _allPaths(RouteBase route) sync* {
  switch (route) {
    case GoRoute():
      yield route.path;
      for (final child in route.routes) {
        yield* _allPaths(child);
      }
    case StatefulShellRoute(:final branches):
      for (final branch in branches) {
        for (final child in branch.routes) {
          yield* _allPaths(child);
        }
      }
    case ShellRoute(:final routes):
      for (final child in routes) {
        yield* _allPaths(child);
      }
    default:
      break;
  }
}

/// WCAG relative-luminance contrast ratio, used above to keep the palette
/// honest instead of asserting hard-coded hex values.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
