import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/tmdb_service.dart';
import '../../shared/models/media_details.dart';
import '../../shared/providers/watchlist_provider.dart';
import '../../shared/widgets/poster_card.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});
  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  final Map<String, Future<MediaDetails>> _cache = {};

  Future<MediaDetails> _load(String key) {
    return _cache.putIfAbsent(key, () async {
      final parts = key.split(':');
      final type = parts[0] == 'tv' ? MediaType.tv : MediaType.movie;
      final id = int.parse(parts[1]);
      final svc = ref.read(tmdbServiceProvider);
      return type == MediaType.movie
          ? svc.getMovieDetails(id)
          : svc.getTvDetails(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(watchlistProvider).toList();
    return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.horizontalPadding),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AppSpacing.lg),
                          Text('Watchlist', style: AppTypography.screenHeading),
                          const SizedBox(height: AppSpacing.sm),
                          Text('Titles you save for later will show up here.',
                              style: AppTypography.body),
                          const Expanded(
                              child: Center(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                Icon(Icons.bookmark_border_rounded,
                                    size: 56, color: AppColors.textMuted),
                                SizedBox(height: AppSpacing.md),
                                Text('Your watchlist is empty',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 16)),
                                SizedBox(height: AppSpacing.xs),
                                Text(
                                    'Tap the bookmark icon on any title to save it.',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13)),
                              ]))),
                        ]))
                : CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                        SliverAppBar(
                            pinned: false,
                            floating: true,
                            snap: true,
                            elevation: 0,
                            backgroundColor: Colors.transparent,
                            title: Text('Watchlist',
                                style: AppTypography.screenHeading),
                            actions: [
                              PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert_rounded),
                                  color: AppColors.surface,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: AppRadii.mdRadius),
                                  onSelected: (v) {
                                    if (v == 'clear') {
                                      ref
                                          .read(watchlistProvider.notifier)
                                          .clear();
                                    }
                                  },
                                  itemBuilder: (_) => [
                                        const PopupMenuItem(
                                            value: 'clear',
                                            child: Text('Clear watchlist'))
                                      ])
                            ]),
                        SliverPadding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.horizontalPadding),
                            sliver: SliverToBoxAdapter(
                                child: Text('${items.length} saved',
                                    style: AppTypography.metadata.copyWith(
                                        color: AppColors.textMuted)))),
                        const SliverToBoxAdapter(
                            child: SizedBox(height: AppSpacing.md)),
                        SliverPadding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.horizontalPadding),
                            sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        crossAxisSpacing: AppSpacing.sm,
                                        mainAxisSpacing: AppSpacing.md,
                                        childAspectRatio: 2 / 3.3),
                                delegate: SliverChildBuilderDelegate(
                                    (context, i) => _WatchlistCell(
                                          key: ValueKey(items[i]),
                                          wlKey: items[i],
                                          loader: _load,
                                          onRemove: () => ref
                                              .read(watchlistProvider.notifier)
                                              .toggle(
                                                  items[i].startsWith('tv:')
                                                      ? MediaType.tv
                                                      : MediaType.movie,
                                                  int.parse(
                                                      items[i].split(':')[1])),
                                        ),
                                    childCount: items.length))),
                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ])));
  }
}

class _WatchlistCell extends StatelessWidget {
  final String wlKey;
  final Future<MediaDetails> Function(String) loader;
  final VoidCallback onRemove;
  const _WatchlistCell(
      {super.key,
      required this.wlKey,
      required this.loader,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final parts = wlKey.split(':');
    final isTv = parts[0] == 'tv';
    return FutureBuilder<MediaDetails>(
        future: loader(wlKey),
        builder: (c, snap) {
          if (!snap.hasData) {
            return Container(
                decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: AppRadii.mdRadius),
                child: const Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.textMuted))));
          }
          final d = snap.data!;
          return Stack(children: [
            PosterCard(
                imageUrl: d.posterUrlW500,
                title: d.title,
                metadata: isTv ? 'TV Series' : d.year,
                onTap: () => context.push(
                    '/details/${isTv ? 'tv' : 'movie'}/${d.id}?poster=${Uri.encodeComponent(d.posterUrlW500)}')),
            Positioned(
                top: 4,
                right: 4,
                child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                        iconSize: 14,
                        padding: const EdgeInsets.all(2),
                        constraints:
                            const BoxConstraints(minWidth: 24, minHeight: 24),
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: onRemove))),
          ]);
        });
  }
}
