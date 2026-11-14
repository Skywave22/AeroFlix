import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/tmdb_service.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/movie.dart';
import '../../shared/models/tv_show.dart';
import '../../shared/widgets/cinematic_hero_banner.dart';
import '../../shared/widgets/horizontal_carousel.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/section_placeholder.dart';
import '../../shared/providers/watchlist_provider.dart';
import '../../app/router.dart';

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

    return Scaffold(
        backgroundColor: AppColors.background,
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
                  SliverAppBar(
                      pinned: false,
                      floating: true,
                      snap: true,
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                      title: Row(children: [
                        Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(6)),
                            child: const Center(
                                child: Icon(Icons.play_arrow_rounded,
                                    color: AppColors.textPrimary, size: 18))),
                        const SizedBox(width: AppSpacing.xs),
                        Text('AeroFlix',
                            style: AppTypography.appBarTitle
                                .copyWith(fontWeight: FontWeight.w700)),
                      ]),
                      actions: [
                        IconButton(
                            icon: const Icon(Icons.notifications_none_rounded),
                            onPressed: () {},
                            splashRadius: 20),
                        const SizedBox(width: AppSpacing.xs)
                      ]),
                  SliverToBoxAdapter(
                      child: trending.when(
                          data: (ms) => ms.isEmpty
                              ? const SizedBox.shrink()
                              : CinematicHeroBanner(
                                  backdropUrl: ms.first.backdropUrlW1280,
                                  title: ms.first.title,
                                  metadata: _meta(ms.first),
                                  description: ms.first.overview,
                                  onPlay: () => _playMovie(ms.first),
                                  onDetails: () => _openMovie(ms.first),
                                  onWatchlist: () => ref
                                      .read(watchlistProvider.notifier)
                                      .toggle(MediaType.movie, ms.first.id),
                                  isInWatchlist: ref.watch(
                                      isInWatchlistProvider(
                                          'movie:${ms.first.id}'))),
                          loading: () =>
                              Container(height: 420, color: AppColors.surface)
                                  .animate(onPlay: (c) => c.repeat())
                                  .shimmer(
                                      duration: 1500.ms,
                                      color: AppColors.surfaceElevated
                                          .withValues(alpha: 0.3)),
                          error: (_, __) => const SizedBox(height: 380))),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  _sliverMovies(trending, 'Trending Now'),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg)),
                  SliverToBoxAdapter(child: _continueEmpty()),
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
  void _openTv(TvShow s) => context.push(
      '/details/tv/${s.id}?poster=${Uri.encodeComponent(s.posterUrlW342)}');
  void _playMovie(Movie m) => context.push('/player',
      extra: PlayerArgs(
          details: MediaDetails(
              type: MediaType.movie,
              id: m.id,
              title: m.title,
              posterPath: m.posterPath,
              backdropPath: m.backdropPath,
              voteAverage: m.voteAverage,
              releaseDate: m.releaseDate)));
  String _meta(Movie m) {
    final p = <String>[];
    if (m.year != null) p.add(m.year!);
    if (m.voteAverage > 0) p.add('★ ${m.rating}');
    return p.join('  ·  ');
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
