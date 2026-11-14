import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

class EpisodesScreen extends ConsumerStatefulWidget {
  final MediaDetails details;
  final int initialSeason;
  const EpisodesScreen(
      {super.key, required this.details, required this.initialSeason});

  @override
  ConsumerState<EpisodesScreen> createState() => _EpisodesScreenState();
}

class _EpisodesScreenState extends ConsumerState<EpisodesScreen> {
  late int _seasonNum;
  late Future<List<Episode>> _future;

  TmdbService get _tmdb => ref.read(tmdbServiceProvider);

  @override
  void initState() {
    super.initState();
    _seasonNum = widget.initialSeason;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _tmdb.getEpisodes(widget.details.id, _seasonNum);
  }

  void _load(int s) {
    setState(() {
      _seasonNum = s;
      _future = _tmdb.getEpisodes(widget.details.id, s);
    });
  }

  PlayerArgs _buildArgs(List<Episode> eps, int index) {
    final ep = eps[index];
    final cw = ref.read(continueWatchingProvider);
    final resumeItem = cw
        .where((i) =>
            i.type == widget.details.type &&
            i.id == widget.details.id &&
            i.season == _seasonNum &&
            i.episode == ep.episodeNumber &&
            !i.isFinished)
        .cast<ContinueWatchingItem?>()
        .firstWhere((_) => true, orElse: () => null);
    final resumeMs = resumeItem?.positionMs ?? 0;

    PlayerArgs? next;
    if (index + 1 < eps.length) {
      final ne = eps[index + 1];
      next = PlayerArgs(
        details: widget.details,
        season: _seasonNum,
        episode: ne.episodeNumber,
        episodeTitle: ne.name,
      );
    } else {
      // Next season's first episode, if a later season exists
      final sortedSeasons = [...widget.details.seasons]
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      final nextSeasonIdx =
          sortedSeasons.indexWhere((s) => s.seasonNumber > _seasonNum);
      if (nextSeasonIdx >= 0) {
        // We don't have episodes loaded for the next season yet;
        // passing season/episode 1 lets player navigate there and
        // re-fetch sources. Episode title will be fetched on the next screen.
        next = PlayerArgs(
          details: widget.details,
          season: sortedSeasons[nextSeasonIdx].seasonNumber,
          episode: 1,
          episodeTitle: 'Next season',
        );
      }
    }

    return PlayerArgs(
      details: widget.details,
      season: _seasonNum,
      episode: ep.episodeNumber,
      episodeTitle: ep.name,
      resumeAtMs: resumeMs,
      nextEpisode: next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedSeasons = [...widget.details.seasons]
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    final cw = ref.watch(continueWatchingProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 120,
          backgroundColor: AppColors.surface,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => context.pop(),
              splashRadius: 20),
          title: Text(widget.details.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.appBarTitle),
          flexibleSpace:
              FlexibleSpaceBar(background: Container(color: AppColors.surface)),
        ),
        SliverToBoxAdapter(
            child: SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.screenHorizontal,
            itemCount: sortedSeasons.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (c, i) {
              final s = sortedSeasons[i];
              final sel = s.seasonNumber == _seasonNum;
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          sel ? AppColors.accent : AppColors.surfaceElevated,
                      foregroundColor:
                          sel ? Colors.white : AppColors.textSecondary,
                    ),
                    onPressed: () => _load(s.seasonNumber),
                    child: Text('S${s.seasonNumber}',
                        style: AppTypography.button.copyWith(fontSize: 13)),
                  ));
            },
          ),
        )),
        FutureBuilder<List<Episode>>(
            future: _future,
            builder: (c, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent, strokeWidth: 2)));
              }
              if (snap.hasError || !snap.hasData) {
                return SliverFillRemaining(
                    child: Center(
                        child: Text('Failed to load episodes',
                            style: AppTypography.bodyPrimary)));
              }
              final eps = snap.data!;
              return SliverList(
                  delegate: SliverChildBuilderDelegate((c, i) {
                final ep = eps[i];
                final itemKey =
                    '${widget.details.type.name}:${widget.details.id}:${_seasonNum}x${ep.episodeNumber.toString().padLeft(2, '0')}';
                final resume = cw
                    .where((x) => x.key == itemKey && !x.isFinished)
                    .cast<ContinueWatchingItem?>()
                    .firstWhere((_) => true, orElse: () => null);
                final progress = resume?.progress ?? 0.0;
                return InkWell(
                  onTap: () =>
                      context.push('/player', extra: _buildArgs(eps, i)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.horizontalPadding,
                        vertical: AppSpacing.sm),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(children: [
                            ClipRRect(
                                borderRadius: AppRadii.smRadius,
                                child: SizedBox(
                                  width: 160,
                                  height: 90,
                                  child: ep.stillUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: ep.stillUrl,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => Container(
                                              color: AppColors.surfaceElevated),
                                          errorWidget: (_, __, ___) =>
                                              Container(
                                                  color:
                                                      AppColors.surfaceElevated,
                                                  child: const Icon(Icons.movie,
                                                      color:
                                                          AppColors.textMuted,
                                                      size: 28)))
                                      : Container(
                                          color: AppColors.surfaceElevated,
                                          child: const Icon(Icons.movie,
                                              color: AppColors.textMuted,
                                              size: 28)),
                                )),
                            if (progress > 0)
                              Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 3,
                                    backgroundColor: Colors.black38,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            AppColors.accent),
                                  )),
                            if (progress > 0)
                              Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.7),
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      child: Text(
                                        '${(progress * 100).round()}%',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600),
                                      ))),
                          ]),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Text('${ep.episodeNumber}. ',
                                      style: AppTypography.cardTitle
                                          .copyWith(color: AppColors.accent)),
                                  Expanded(
                                      child: Text(ep.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.cardTitle)),
                                ]),
                                if (ep.airDate != null &&
                                    ep.airDate!.isNotEmpty)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(ep.airDate!.substring(0, 10),
                                          style: AppTypography.metadata
                                              .copyWith(
                                                  color: AppColors.textMuted))),
                                if (ep.overview.isNotEmpty)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(ep.overview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.metadata
                                              .copyWith(
                                                  color: AppColors
                                                      .textSecondary))),
                                if (resume != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Row(children: [
                                        const Icon(Icons.history_rounded,
                                            size: 12, color: AppColors.accent),
                                        const SizedBox(width: 4),
                                        Text('Resume',
                                            style: AppTypography.metadata
                                                .copyWith(
                                                    color: AppColors.accent,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                      ])),
                              ])),
                          Icon(
                              resume != null
                                  ? Icons.play_circle_filled_rounded
                                  : Icons.play_circle_outline_rounded,
                              color: resume != null
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              size: 28),
                        ]),
                  ),
                );
              }, childCount: eps.length));
            }),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ]),
    );
  }
}
