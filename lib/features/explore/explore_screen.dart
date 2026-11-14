import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/tmdb_service.dart';
import '../../shared/models/movie.dart';
import '../../shared/models/tv_show.dart';
import '../../shared/widgets/category_chip.dart';
import '../../shared/widgets/poster_card.dart';

final _exploreMoviesProvider =
    FutureProvider.family<List<Movie>, int>((ref, genreId) {
  return ref.watch(tmdbServiceProvider).getMoviesByGenre(genreId);
});
final _exploreTvProvider =
    FutureProvider.family<List<TvShow>, int>((ref, genreId) {
  return ref.watch(tmdbServiceProvider).getTvByGenre(genreId);
});

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  int? _selGenreId;
  String _selLabel = 'All';
  bool _tvMode = false;

  static const _presets = <_Preset>[
    _Preset(label: 'All', id: null),
    _Preset(label: 'Bollywood', id: -1),
    _Preset(label: 'Action', id: 28),
    _Preset(label: 'Comedy', id: 35),
    _Preset(label: 'Drama', id: 18),
    _Preset(label: 'Horror', id: 27),
    _Preset(label: 'Sci-Fi', id: 878),
    _Preset(label: 'Thriller', id: 53),
    _Preset(label: 'Romance', id: 10749),
    _Preset(label: 'Animation', id: 16),
    _Preset(label: 'Documentary', id: 99),
  ];

  void _openMovie(Movie m) => context.push(
      '/details/movie/${m.id}?poster=${Uri.encodeComponent(m.posterUrlW342)}');
  void _openTv(TvShow s) => context.push(
      '/details/tv/${s.id}?poster=${Uri.encodeComponent(s.posterUrlW342)}');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.background,
        body: RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async {
              ref.invalidate(trendingMoviesProvider);
              ref.invalidate(popularMoviesProvider);
              ref.invalidate(trendingTvProvider);
              ref.invalidate(popularTvProvider);
              ref.invalidate(hindiMoviesProvider);
              if (_selGenreId != null && _selGenreId! > 0) {
                ref.invalidate(_tvMode
                    ? _exploreTvProvider(_selGenreId!)
                    : _exploreMoviesProvider(_selGenreId!));
              }
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
                      title:
                          Text('Explore', style: AppTypography.screenHeading)),
                  SliverToBoxAdapter(
                      child: SizedBox(
                          height: 44,
                          child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.horizontalPadding),
                              itemCount: _presets.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: AppSpacing.xs),
                              itemBuilder: (_, i) {
                                final p = _presets[i];
                                return CategoryChip(
                                    label: p.label,
                                    selected: _selLabel == p.label,
                                    onTap: () => setState(() {
                                          _selLabel = p.label;
                                          _selGenreId = p.id;
                                        }));
                              }))),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.sm)),
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.horizontalPadding),
                          child: Row(children: [
                            _toggle('Movies', !_tvMode,
                                () => setState(() => _tvMode = false)),
                            const SizedBox(width: AppSpacing.sm),
                            _toggle('TV Shows', _tvMode,
                                () => setState(() => _tvMode = true)),
                          ]))),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.md)),
                  _buildContent(),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ])));
  }

  Widget _toggle(String label, bool sel, VoidCallback onTap) {
    return Expanded(
        child: Material(
            color: sel ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: onTap,
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                        child: Text(label,
                            style: AppTypography.button.copyWith(
                                color: sel
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontSize: 13)))))));
  }

  Widget _buildContent() {
    if (_selGenreId == null) return _buildDefault();
    if (_selGenreId == -1) {
      return _sliverGridAsync(ref.watch(hindiMoviesProvider), false);
    }
    final async = _tvMode
        ? ref.watch(_exploreTvProvider(_selGenreId!))
        : ref.watch(_exploreMoviesProvider(_selGenreId!));
    return _sliverGridAsync(async, _tvMode);
  }

  Widget _buildDefault() {
    final popAsync = _tvMode
        ? ref.watch(popularTvProvider)
        : ref.watch(popularMoviesProvider);
    final trendAsync = _tvMode
        ? ref.watch(trendingTvProvider)
        : ref.watch(trendingMoviesProvider);
    return SliverToBoxAdapter(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Trending Now'),
      const SizedBox(height: AppSpacing.sm),
      _horizontal(trendAsync, _tvMode),
      const SizedBox(height: AppSpacing.lg),
      _sectionTitle('Popular'),
      const SizedBox(height: AppSpacing.sm),
      _horizontal(popAsync, _tvMode),
    ]));
  }

  Widget _sectionTitle(String t) => Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.horizontalPadding),
      child: Text(t, style: AppTypography.sectionHeading));

  Widget _horizontal(AsyncValue<List<dynamic>> async, bool isTv) {
    return SizedBox(
        height: AppSpacing.posterHeight + 56,
        child: async.when(
            data: (items) => ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.horizontalPadding),
                physics: const BouncingScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.md),
                itemBuilder: (_, i) {
                  final it = items[i];
                  if (isTv) {
                    final s = it as TvShow;
                    return PosterCard(
                        imageUrl: s.posterUrlW342,
                        title: s.name,
                        metadata: s.year,
                        onTap: () => _openTv(s));
                  }
                  final m = it as Movie;
                  return PosterCard(
                      imageUrl: m.posterUrlW342,
                      title: m.title,
                      metadata: m.year,
                      onTap: () => _openMovie(m));
                }),
            loading: () => const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                        color: AppColors.accent, strokeWidth: 2))),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load: $e',
                    style: const TextStyle(color: AppColors.textMuted)))));
  }

  Widget _sliverGridAsync(AsyncValue<List<dynamic>> async, bool isTv) {
    return SliverPadding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.horizontalPadding),
        sliver: async.when(
            data: (items) => SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 2 / 3.3),
                delegate: SliverChildBuilderDelegate((c, i) {
                  final it = items[i];
                  if (isTv) {
                    final s = it as TvShow;
                    return PosterCard(
                        imageUrl: s.posterUrlW342,
                        title: s.name,
                        metadata: s.year,
                        onTap: () => _openTv(s));
                  }
                  final m = it as Movie;
                  return PosterCard(
                      imageUrl: m.posterUrlW342,
                      title: m.title,
                      metadata: m.year,
                      onTap: () => _openMovie(m));
                }, childCount: items.length)),
            loading: () => const SliverFillRemaining(
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accent, strokeWidth: 2))),
            error: (_, __) => SliverFillRemaining(
                    child: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.textMuted, size: 40),
                  const SizedBox(height: 12),
                  Text('Could not load results',
                      style: AppTypography.bodyPrimary),
                ])))));
  }
}

class _Preset {
  final String label;
  final int? id;
  const _Preset({required this.label, this.id});
}
