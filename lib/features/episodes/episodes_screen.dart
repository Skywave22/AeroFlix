import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../shared/widgets/section_placeholder.dart';
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
    final itemKey =
        '${widget.details.type.name}:${widget.details.id}:${_seasonNum}x${ep.episodeNumber.toString().padLeft(2, '0')}';
    ContinueWatchingItem? resumeItem;
    for (final i in cw) {
      if (i.key == itemKey && !i.isFinished) {
        resumeItem = i;
        break;
      }
    }
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
      final sortedSeasons = [...widget.details.seasons]
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      final nextSeasonIdx =
          sortedSeasons.indexWhere((s) => s.seasonNumber > _seasonNum);
      if (nextSeasonIdx >= 0) {
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
        body: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            setState(() {
              _future = _tmdb.getEpisodes(widget.details.id, _seasonNum);
            });
          },
          child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 120,
                  backgroundColor: AppColors.surface,
                  leading: IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => context.pop(),
                      splashRadius: 20),
                  title: Text(widget.details.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.appBarTitle),
                  flexibleSpace: FlexibleSpaceBar(
                      background: Container(color: AppColors.surface)),
                ),
                SliverToBoxAdapter(
                    child: SizedBox(
                        height: 56,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: AppSpacing.screenHorizontal,
                          itemCount: sortedSeasons.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: AppSpacing.sm),
                          itemBuilder: (c, i) {
                            final s = sortedSeasons[i];
                            final sel = s.seasonNumber == _seasonNum;
                            return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: sel
                                        ? AppColors.accent
                                        : AppColors.surfaceElevated,
                                    foregroundColor: sel
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                  onPressed: () => _load(s.seasonNumber),
                                  child: Text('S${s.seasonNumber}',
                                      style: AppTypography.button
                                          .copyWith(fontSize: 13)),
                                ));
                          },
                        ))),
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
                        // Was a dead-end message with no way to recover.
                        return SliverFillRemaining(
                            child: Center(
                                child: SectionErrorState(
                                    message:
                                        'Could not load this season’s episodes',
                                    onRetry: () => _load(_seasonNum))));
                      }
                      final eps = snap.data!;
                      if (eps.isEmpty) {
                        return const SliverFillRemaining(
                            child: Center(
                                child: SectionEmptyState(
                                    message:
                                        'No episodes listed for this season.',
                                    icon: Icons.live_tv_outlined)));
                      }
                      return SliverList(
                          delegate: SliverChildBuilderDelegate((c, i) {
                        final ep = eps[i];
                        final itemKey =
                            '${widget.details.type.name}:${widget.details.id}:${_seasonNum}x${ep.episodeNumber.toString().padLeft(2, '0')}';
                        ContinueWatchingItem? resume;
                        for (final x in cw) {
                          if (x.key == itemKey && !x.isFinished) {
                            resume = x;
                            break;
                          }
                        }
                        final progress = resume?.progress ?? 0.0;
                        return InkWell(
                          onTap: () => context.push('/player',
                              extra: _buildArgs(eps, i)),
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
                                                  placeholder: (_, __) =>
                                                      Container(
                                                          color: AppColors
                                                              .surfaceElevated),
                                                  errorWidget: (_, __, ___) =>
                                                      Container(
                                                          color: AppColors
                                                              .surfaceElevated,
                                                          child: const Icon(
                                                              Icons.movie,
                                                              color: AppColors
                                                                  .textMuted,
                                                              size: 28)))
                                              : Container(
                                                  color:
                                                      AppColors.surfaceElevated,
                                                  child: const Icon(Icons.movie,
                                                      color:
                                                          AppColors.textMuted,
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
                                                const AlwaysStoppedAnimation<
                                                    Color>(AppColors.accent),
                                          )),
                                    if (progress > 0)
                                      Positioned(
                                          bottom: 6,
                                          right: 6,
                                          child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 2),
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
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ))),
                                  ]),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Row(children: [
                                          Text('${ep.episodeNumber}. ',
                                              style: AppTypography.cardTitle
                                                  .copyWith(
                                                      color: AppColors.accent)),
                                          Expanded(
                                              child: Text(ep.name,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      AppTypography.cardTitle)),
                                          if (_isUpcoming(ep.airDate)) ...[
                                            const SizedBox(width: 6),
                                            _UpcomingBadge(),
                                          ] else if (_isNew(ep.airDate)) ...[
                                            const SizedBox(width: 6),
                                            _NewBadge(),
                                          ],
                                        ]),
                                        if ((ep.airDate != null &&
                                                ep.airDate!.isNotEmpty) ||
                                            ep.voteAverage > 0)
                                          Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Row(children: [
                                                if (ep.airDate != null &&
                                                    ep.airDate!.isNotEmpty)
                                                  Text(
                                                      ep.airDate!
                                                          .substring(0, 10),
                                                      style: AppTypography
                                                          .metadata
                                                          .copyWith(
                                                              color: AppColors
                                                                  .textMuted)),
                                                if ((ep.airDate != null &&
                                                        ep.airDate!
                                                            .isNotEmpty) &&
                                                    ep.voteAverage > 0)
                                                  const Text('  ·  ',
                                                      style: TextStyle(
                                                          color: AppColors
                                                              .textMuted,
                                                          fontSize: 11)),
                                                if (ep.voteAverage > 0)
                                                  Row(children: [
                                                    const Icon(
                                                        Icons.star_rounded,
                                                        size: 12,
                                                        color:
                                                            AppColors.accent),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                        ep.voteAverage
                                                            .toStringAsFixed(1),
                                                        style: AppTypography
                                                            .metadata
                                                            .copyWith(
                                                                color: AppColors
                                                                    .textSecondary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600)),
                                                  ]),
                                              ])),
                                        if (ep.overview.isNotEmpty)
                                          Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Text(ep.overview,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: AppTypography.metadata
                                                      .copyWith(
                                                          color: AppColors
                                                              .textSecondary))),
                                        if (resume != null)
                                          Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 6),
                                              child: Row(children: [
                                                const Icon(
                                                    Icons.history_rounded,
                                                    size: 12,
                                                    color: AppColors.accent),
                                                const SizedBox(width: 4),
                                                Text('Resume',
                                                    style: AppTypography
                                                        .metadata
                                                        .copyWith(
                                                            color: AppColors
                                                                .accent,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)),
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
        ));
  }

  bool _isNew(String? airDate) {
    if (airDate == null || airDate.length < 10) return false;
    try {
      final d = DateTime.parse(airDate.substring(0, 10));
      return DateTime.now().difference(d).inDays < 30 &&
          !d.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  bool _isUpcoming(String? airDate) {
    if (airDate == null || airDate.length < 10) return false;
    try {
      final d = DateTime.parse(airDate.substring(0, 10));
      return d.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }
}

class _NewBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: AppColors.accent, borderRadius: BorderRadius.circular(4)),
      child: Text('NEW',
          style: AppTypography.metadata.copyWith(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)));
}

class _UpcomingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: AppColors.warning, borderRadius: BorderRadius.circular(4)),
      child: Text('UPCOMING',
          style: AppTypography.metadata.copyWith(
              color: Colors.black,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)));
}
