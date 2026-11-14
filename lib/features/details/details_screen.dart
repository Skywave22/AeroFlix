import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/tmdb_service.dart';
import '../../shared/models/media_details.dart';
import '../../shared/providers/continue_watching_provider.dart';
import '../../shared/providers/watchlist_provider.dart';
import '../../shared/widgets/horizontal_carousel.dart';
import '../../shared/widgets/poster_card.dart';

/// Arguments passed to the details route via GoRouter extra.
class DetailsArgs {
  final int id;
  final MediaType type;
  final String? posterUrl;
  const DetailsArgs({required this.id, required this.type, this.posterUrl});
}

class DetailsScreen extends ConsumerStatefulWidget {
  final DetailsArgs args;
  const DetailsScreen({super.key, required this.args});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  late Future<MediaDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MediaDetails> _load() {
    final svc = ref.read(tmdbServiceProvider);
    return widget.args.type == MediaType.movie
        ? svc.getMovieDetails(widget.args.id)
        : svc.getTvDetails(widget.args.id);
  }

  @override
  Widget build(BuildContext context) {
    final watchKey = '${widget.args.type.name}:${widget.args.id}';
    final inWatchlist = ref.watch(isInWatchlistProvider(watchKey));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<MediaDetails>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return CustomScrollView(slivers: [
              _appBar(context),
              const SliverFillRemaining(
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.accent))),
            ]);
          }
          if (snap.hasError) {
            return CustomScrollView(slivers: [
              _appBar(context),
              SliverFillRemaining(
                  child: Center(
                      child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.error, size: 40),
                            const SizedBox(height: AppSpacing.md),
                            Text('Something went wrong loading this title.',
                                style: AppTypography.body,
                                textAlign: TextAlign.center),
                            const SizedBox(height: AppSpacing.md),
                            FilledButton(
                                onPressed: () =>
                                    setState(() => _future = _load()),
                                child: const Text('Retry')),
                          ])))),
            ]);
          }
          final d = snap.data!;
          return _DetailsContent(details: d, inWatchlist: inWatchlist);
        },
      ),
    );
  }

  SliverAppBar _appBar(BuildContext context) => SliverAppBar(
        pinned: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => context.pop(),
            splashRadius: 20),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      );
}

class _DetailsContent extends ConsumerWidget {
  final MediaDetails details;
  final bool inWatchlist;
  const _DetailsContent({required this.details, required this.inWatchlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = details.genreNames.take(3).join('  ·  ');
    final metaParts = <String>[];
    if (details.year != null) metaParts.add(details.year!);
    if (genres.isNotEmpty) metaParts.add(genres);
    if (details.runtimeLabel.isNotEmpty) metaParts.add(details.runtimeLabel);
    if (details.voteAverage > 0) metaParts.add('★ ${details.rating}');
    if (details.type == MediaType.tv && details.numberOfSeasons > 0) {
      metaParts.add(
          '${details.numberOfSeasons} Season${details.numberOfSeasons > 1 ? 's' : ''}');
    }

    return CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
      // Backdrop header
      SliverAppBar(
        pinned: true,
        expandedHeight: 320,
        backgroundColor: AppColors.background,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 20),
        actions: [
          IconButton(
            icon: Icon(inWatchlist ? Icons.bookmark : Icons.bookmark_border),
            color: inWatchlist ? AppColors.accent : AppColors.textPrimary,
            onPressed: () => ref
                .read(watchlistProvider.notifier)
                .toggle(details.type, details.id),
            splashRadius: 20,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
          if (details.backdropUrlW1280.isNotEmpty)
            CachedNetworkImage(
                imageUrl: details.backdropUrlW1280,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter)
          else
            Container(color: AppColors.surface),
          const DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66090A0D), AppColors.background],
                      stops: [0.0, 1.0]))),
        ])),
      ),

      // Title + metadata + CTAs
      SliverToBoxAdapter(
          child: Padding(
              padding: AppSpacing.screenHorizontal,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(details.title,
                        style: AppTypography.display.copyWith(fontSize: 28)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(metaParts.join('  ·  '), style: AppTypography.body),
                    if (details.tagline != null &&
                        details.tagline!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(details.tagline!,
                          style: AppTypography.metadata.copyWith(
                              fontStyle: FontStyle.italic,
                              color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Row(children: [
                      Expanded(child: Builder(builder: (ctx) {
                        final cw = ref.watch(continueWatchingProvider);
                        // For TV: find any unfinished episode for this show
                        ContinueWatchingItem? tvResume;
                        if (details.type == MediaType.tv) {
                          for (final i in cw) {
                            if (i.type == MediaType.tv &&
                                i.id == details.id &&
                                !i.isFinished) {
                              tvResume = i;
                              break;
                            }
                          }
                        }
                        // For movies: s=0,e=0
                        ContinueWatchingItem? movieResume;
                        if (details.type == MediaType.movie) {
                          final key = '${details.type.name}:${details.id}:0x00';
                          for (final i in cw) {
                            if (i.key == key && !i.isFinished) {
                              movieResume = i;
                              break;
                            }
                          }
                        }

                        final isTv = details.type == MediaType.tv;
                        final resume = isTv ? tvResume : movieResume;
                        final label = isTv
                            ? (resume != null
                                ? 'Resume S${resume.season}E${resume.episode}'
                                : 'Episodes')
                            : (resume != null ? 'Resume' : 'Play');
                        final icon = isTv && resume == null
                            ? Icons.format_list_bulleted_rounded
                            : Icons.play_arrow_rounded;

                        return FilledButton.icon(
                            onPressed: () {
                              if (isTv && resume != null) {
                                context.push('/player',
                                    extra: PlayerArgs(
                                      details: details,
                                      season: resume.season,
                                      episode: resume.episode,
                                      episodeTitle: resume.episodeTitle,
                                      resumeAtMs: resume.positionMs,
                                    ));
                              } else if (isTv) {
                                final sorted = [...details.seasons]
                                  ..sort((a, b) =>
                                      a.seasonNumber.compareTo(b.seasonNumber));
                                final firstSeason = sorted.isNotEmpty
                                    ? sorted.first.seasonNumber
                                    : 1;
                                context.push('/episodes',
                                    extra: EpisodesArgs(
                                        details: details,
                                        initialSeason: firstSeason));
                              } else {
                                context.push('/player',
                                    extra: PlayerArgs(
                                      details: details,
                                      resumeAtMs: resume?.positionMs ?? 0,
                                    ));
                              }
                            },
                            icon: Icon(icon, size: 22),
                            label: Text(label));
                      })),
                      const SizedBox(width: AppSpacing.sm),
                      _IconPill(
                          icon: inWatchlist
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          active: inWatchlist,
                          onTap: () => ref
                              .read(watchlistProvider.notifier)
                              .toggle(details.type, details.id)),
                      const SizedBox(width: AppSpacing.sm),
                      _IconPill(icon: Icons.download_outlined, onTap: () {}),
                      const SizedBox(width: AppSpacing.sm),
                      _IconPill(icon: Icons.share_outlined, onTap: () {}),
                    ]),
                    if (details.overview != null &&
                        details.overview!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(details.overview!,
                          style: AppTypography.body.copyWith(
                              color: AppColors.textPrimary, height: 1.6)),
                    ],
                  ]))),

      // Cast
      if (details.cast.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
            child: Padding(
                padding: AppSpacing.screenHorizontal,
                child: Text('Cast', style: AppTypography.sectionHeading))),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
        SliverToBoxAdapter(
            child: SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: AppSpacing.screenHorizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: details.cast.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (_, i) {
                    final c = details.cast[i];
                    return SizedBox(
                        width: 72,
                        child: Column(children: [
                          ClipOval(
                            child: SizedBox(
                                width: 56,
                                height: 56,
                                child: c.profileUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: c.profileUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) =>
                                            Container(color: AppColors.surface),
                                        errorWidget: (_, __, ___) => Container(
                                            color: AppColors.surface,
                                            child: const Icon(Icons.person,
                                                color: AppColors.textMuted,
                                                size: 24)))
                                    : Container(
                                        color: AppColors.surface,
                                        child: const Icon(Icons.person,
                                            color: AppColors.textMuted,
                                            size: 24))),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.metadata.copyWith(
                                  color: AppColors.textPrimary, fontSize: 11)),
                          if (c.character.isNotEmpty)
                            Text(c.character,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.metadata
                                    .copyWith(fontSize: 10)),
                        ]));
                  },
                ))),
      ],

      // Seasons (TV only)
      if (details.type == MediaType.tv && details.seasons.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
            child: Padding(
                padding: AppSpacing.screenHorizontal,
                child: Text('Seasons', style: AppTypography.sectionHeading))),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
        SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
          final s = details.seasons[i];
          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.horizontalPadding,
                vertical: AppSpacing.xs),
            child: Material(
              color: AppColors.surface,
              borderRadius: AppRadii.mdRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push('/episodes',
                    extra: EpisodesArgs(
                        details: details, initialSeason: s.seasonNumber)),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: AppRadii.smRadius,
                      child: SizedBox(
                          width: 72,
                          height: 104,
                          child: s.posterUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: s.posterUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                      color: AppColors.surfaceElevated),
                                  errorWidget: (_, __, ___) => Container(
                                      color: AppColors.surfaceElevated,
                                      child: const Icon(Icons.tv,
                                          color: AppColors.textMuted,
                                          size: 24)))
                              : Container(
                                  color: AppColors.surfaceElevated,
                                  child: const Icon(Icons.tv,
                                      color: AppColors.textMuted, size: 24))),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(s.name, style: AppTypography.cardTitle),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                              '${s.episodeCount} Episodes${s.airDate != null && s.airDate!.isNotEmpty ? ' · ${s.airDate!.substring(0, 4)}' : ''}',
                              style: AppTypography.metadata),
                          if (s.overview.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(s.overview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.metadata
                                    .copyWith(color: AppColors.textMuted)),
                          ],
                        ])),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                  ]),
                ),
              ),
            ),
          );
        }, childCount: details.seasons.length)),
      ],

      // More Like This
      if (details.similar.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
            child: HorizontalCarousel(
                title: 'More Like This',
                itemCount: details.similar.length,
                height: AppSpacing.posterHeight + 56,
                itemBuilder: (_, i) {
                  final s = details.similar[i];
                  return PosterCard(
                      imageUrl: s.posterUrlW342,
                      title: s.title,
                      metadata: s.year,
                      onTap: () => context.push(
                          '/details/${s.type == MediaType.tv ? 'tv' : 'movie'}/${s.id}?poster=${Uri.encodeComponent(s.posterUrlW342)}'));
                })),
      ],

      const SliverToBoxAdapter(child: SizedBox(height: 100)),
    ]);
  }
}

class _IconPill extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  const _IconPill({required this.icon, this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => Material(
      color: AppColors.surface,
      borderRadius: AppRadii.lgRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icon,
                  size: 20,
                  color: active ? AppColors.accent : AppColors.textPrimary))));
}
