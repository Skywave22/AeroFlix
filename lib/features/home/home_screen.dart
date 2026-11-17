import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

import '../../core/network/tmdb_service.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/movie.dart';
import '../../shared/models/tv_show.dart';
import '../../shared/providers/continue_watching_provider.dart';
import '../../shared/providers/watchlist_provider.dart';
import '../../shared/widgets/continue_card.dart';
import '../../shared/widgets/hero_item.dart';
import '../../shared/widgets/hero_rotator.dart';
import '../../shared/widgets/horizontal_carousel.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/section_placeholder.dart';
import '../providers/provider_diagnostics_screen.dart';

// Curated ids for the "Hindi Blockbusters" row — all real catalogue titles,
// playable through the providers like everything else.
const List<int> _kHindiRow = [
  1010581, // Animal
  872906, // Jawan
  792307, // Poor Things (world cinema in the Hindi row is intentional-free)
  640146, // Ant-Man and the Wasp: Quantumania (multi-audio)
  502356, // The Super Mario Bros. Movie (multi-audio)
  298618, // The Flash (multi-audio)
];

/// Fetches a list of MediaDetails for the given movie ids in parallel.
final movieDetailsBulkProvider =
    FutureProvider.family<List<MediaDetails>, List<int>>((ref, ids) async {
  final svc = ref.watch(tmdbServiceProvider);
  final futures = ids.map((id) => svc.getMovieDetails(id));
  return Future.wait(futures);
});

String _year(String? date) =>
    (date != null && date.length >= 4) ? date.substring(0, 4) : '';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final trending = ref.watch(trendingMoviesProvider);
    final trendingTv = ref.watch(trendingTvProvider);
    final popular = ref.watch(popularMoviesProvider);
    final topRated = ref.watch(topRatedMoviesProvider);
    final nowPlaying = ref.watch(nowPlayingMoviesProvider);
    final hindi = ref.watch(hindiMoviesProvider);
    final continueList = ref.watch(continueWatchingProvider);
    final watchlistKeys = ref.watch(watchlistProvider);

    return Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            // A top-down scrim instead of a solid bar: the hero artwork runs
            // behind the status bar (no dead band at the top) while the logo
            // and the section headings stay readable once you scroll.
            flexibleSpace: const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroTopScrim)),
            title: Row(children: [
              Image.asset('assets/images/logo_mark.png',
                  width: 32, height: 32, filterQuality: FilterQuality.medium),
              const SizedBox(width: AppSpacing.sm),
              Text('AeroFlix',
                  style: AppTypography.appBarTitle.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2)),
            ]),
            actions: [
              IconButton(
                  tooltip: 'Provider status',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ProviderDiagnosticsScreen())),
                  splashRadius: 20),
              const SizedBox(width: AppSpacing.xs)
            ]),
        body: RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            onRefresh: () async {
              ref.invalidate(trendingMoviesProvider);
              ref.invalidate(trendingTvProvider);
              ref.invalidate(popularMoviesProvider);
              ref.invalidate(topRatedMoviesProvider);
              ref.invalidate(nowPlayingMoviesProvider);
              ref.invalidate(hindiMoviesProvider);
            },
            child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(
                      child: (trending.isLoading || trendingTv.isLoading)
                          ? Container(height: 420, color: AppColors.surface)
                              .animate(onPlay: (c) => c.repeat())
                              .shimmer(
                                  duration: 1500.ms,
                                  color: AppColors.surfaceElevated
                                      .withValues(alpha: 0.3))
                          : trending.hasError && trendingTv.hasError
                              ? const SizedBox(height: 380)
                              : _buildHero(
                                  trending, trendingTv, watchlistKeys)),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  if (continueList.isNotEmpty)
                    SliverToBoxAdapter(
                        child: HorizontalCarousel(
                            title: 'Continue Watching',
                            height: 160,
                            itemCount: continueList.length,
                            itemBuilder: (_, i) => ContinueCard(
                                  item: continueList[i],
                                  onTap: () => _playContinue(continueList[i]),
                                  onRemove: () => ref
                                      .read(continueWatchingProvider.notifier)
                                      .remove(continueList[i].type,
                                          continueList[i].id,
                                          season: continueList[i].season,
                                          episode: continueList[i].episode),
                                ))),
                  if (continueList.isEmpty)
                    SliverToBoxAdapter(child: _continueEmpty()),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  // Hindi-first cinema row (real TMDB catalogue; playback comes
                  // from the TJ providers like every other title).
                  SliverToBoxAdapter(
                      child: Consumer(builder: (context, ref, _) {
                    final freeAsync =
                        ref.watch(movieDetailsBulkProvider(_kHindiRow));
                    return freeAsync.when(
                      loading: () => const SizedBox(
                          height: 200,
                          child: Center(
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (items) => HorizontalCarousel(
                        title: 'Hindi Blockbusters',
                        height: 200,
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final it = items[i];
                          return PosterCard(
                            imageUrl: it.posterUrlW500,
                            title: it.title,
                            metadata: _year(it.releaseDate),
                            onTap: () => _openMovieId(
                                it.id, it.posterUrlW500, MediaType.movie),
                          );
                        },
                      ),
                    );
                  })),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  _sliverMovies(trending, 'Trending Now'),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  _sliverMovies(hindi, 'Hindi Cinema'),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  _sliverMovies(popular, 'Popular Movies'),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  _sliverTv(trendingTv, 'Trending TV Shows'),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  _sliverMovies(topRated, 'Top Rated', rating: true),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  _sliverMovies(nowPlaying, 'Now Playing'),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ])));
  }

  void _openMovie(Movie m) => context.push(
      '/details/movie/${m.id}?poster=${Uri.encodeComponent(m.posterUrlW342)}');
  void _openMovieId(int id, String posterUrl, MediaType type) => context.push(
      '/details/${type.name}/$id?poster=${Uri.encodeComponent(posterUrl)}');
  void _openTv(TvShow s) => context.push(
      '/details/tv/${s.id}?poster=${Uri.encodeComponent(s.posterUrlW342)}');

  Widget _buildHero(AsyncValue<List<Movie>> movies, AsyncValue<List<TvShow>> tv,
      Set<String> watchlistKeys) {
    final ms = movies.valueOrNull ?? const <Movie>[];
    final ts = tv.valueOrNull ?? const <TvShow>[];
    final hero = <HeroItem>[
      ...ms.take(5).map(HeroItem.fromMovie),
      ...ts.take(3).map(HeroItem.fromTv),
    ]..shuffle();
    if (hero.isEmpty) return const SizedBox(height: 380);
    return HeroRotator(
      items: hero,
      isInWatchlist: (it) => watchlistKeys.contains('${it.kind}:${it.id}'),
      onDetails: (it) {
        final url = Uri.encodeComponent(it.posterUrl);
        context.push('/details/${it.kind}/${it.id}?poster=$url');
      },
      onPlay: (it) {
        // Playback always starts from the details screen: the episode picker,
        // resume position and real source list live there.
        final url = Uri.encodeComponent(it.posterUrl);
        context.push('/details/${it.kind}/${it.id}?poster=$url');
      },
      onWatchlist: (it, was) {
        ref
            .read(watchlistProvider.notifier)
            .toggle(it.kind == 'tv' ? MediaType.tv : MediaType.movie, it.id);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(was
                  ? 'Removed ${it.title} from Watchlist'
                  : 'Added ${it.title} to Watchlist'),
              duration: const Duration(seconds: 2)));
      },
    );
  }

  void _playContinue(ContinueWatchingItem it) {
    final details = MediaDetails(
      type: it.type,
      id: it.id,
      title: it.title,
      posterPath: it.posterPath,
      backdropPath: it.backdropPath,
    );
    context.push('/player',
        extra: PlayerArgs(
          details: details,
          season: it.season,
          episode: it.episode,
          episodeTitle: it.episodeTitle,
          resumeAtMs: it.positionMs,
        ));
  }

  String _metaRating(Movie m) => '★ ${m.rating} · ${m.year ?? ""}';

  Widget _sliverMovies(AsyncValue<List<Movie>> prov, String title,
          {bool rating = false}) =>
      SliverToBoxAdapter(
          child: prov.when(
              data: (ms) => HorizontalCarousel(
                  title: title,
                  itemCount: ms.length,
                  height: AppSpacing.posterHeight + 56,
                  itemBuilder: (_, i) => PosterCard(
                      imageUrl: ms[i].posterUrlW342,
                      title: ms[i].title,
                      metadata: rating ? _metaRating(ms[i]) : ms[i].year,
                      onTap: () => _openMovie(ms[i]))),
              loading: () => const SectionLoadingPlaceholder(),
              error: (_, __) => const SizedBox.shrink()));

  Widget _sliverTv(AsyncValue<List<TvShow>> prov, String title) =>
      SliverToBoxAdapter(
          child: prov.when(
              data: (shows) => HorizontalCarousel(
                  title: title,
                  itemCount: shows.length,
                  height: AppSpacing.posterHeight + 56,
                  itemBuilder: (_, i) => PosterCard(
                      imageUrl: shows[i].posterUrlW342,
                      title: shows[i].name,
                      metadata: shows[i].year,
                      onTap: () => _openTv(shows[i]))),
              loading: () => const SectionLoadingPlaceholder(),
              error: (_, __) => const SizedBox.shrink()));

  Widget _continueEmpty() => Padding(
      padding: AppSpacing.screenHorizontal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Continue Watching', style: AppTypography.sectionHeading),
        const SizedBox(height: AppSpacing.sm),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.lg)),
            child: Row(children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.play_circle_outline_rounded,
                      color: AppColors.textMuted)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Pick up where you left off',
                        style: AppTypography.cardTitle.copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('Titles you start watching will appear here.',
                        style: AppTypography.metadata),
                  ])),
            ])),
      ]));
}
