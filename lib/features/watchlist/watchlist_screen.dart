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
      // "movie:123" — a corrupt entry must not crash the whole tab.
      final id = int.tryParse(parts.length > 1 ? parts[1] : '');
      if (id == null) {
        return MediaDetails(type: type, id: 0, title: 'Unavailable');
      }
      final svc = ref.read(tmdbServiceProvider);
      return type == MediaType.movie
          ? svc.getMovieDetails(id)
          : svc.getTvDetails(id);
    });
  }

  Future<bool> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear watchlist?'),
        content: const Text(
          'Every saved title will be removed from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    return ok ?? false;
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
                  horizontal: AppSpacing.horizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    Text('Watchlist', style: AppTypography.screenHeading),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Titles you save for later will show up here.',
                      style: AppTypography.body,
                    ),
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bookmark_border_rounded,
                              size: 56,
                              color: AppColors.textMuted,
                            ),
                            SizedBox(height: AppSpacing.md),
                            Text(
                              'Your watchlist is empty',
                              style: AppTypography.cardTitle,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Tap the bookmark icon on any title to save it.',
                              textAlign: TextAlign.center,
                              style: AppTypography.metadata.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    pinned: false,
                    floating: true,
                    snap: true,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    title: Text(
                      'Watchlist',
                      style: AppTypography.screenHeading,
                    ),
                    actions: [
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded),
                        color: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.mdRadius,
                        ),
                        onSelected: (v) async {
                          if (v != 'clear') return;
                          final ok = await _confirmClear(context);
                          if (!ok) return;
                          if (context.mounted) {
                            await ref.read(watchlistProvider.notifier).clear();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'clear',
                            child: Text('Clear watchlist'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.horizontalPadding,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        '${items.length} saved',
                        style: AppTypography.metadata.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.md),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.horizontalPadding,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: AppSpacing.posterColumnsFor(context),
                        crossAxisSpacing: AppSpacing.sm,
                        mainAxisSpacing: AppSpacing.md,
                        mainAxisExtent: AppSpacing.posterRowFor(context) - 16,
                      ),
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
                                int.parse(items[i].split(':')[1]),
                              ),
                        ),
                        childCount: items.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 24 + MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _WatchlistCell extends StatelessWidget {
  final String wlKey;
  final Future<MediaDetails> Function(String) loader;
  final VoidCallback onRemove;
  const _WatchlistCell({
    super.key,
    required this.wlKey,
    required this.loader,
    required this.onRemove,
  });

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
              color: AppColors.surface,
              borderRadius: AppRadii.mdRadius,
            ),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          );
        }
        final d = snap.data!;
        return Stack(
          children: [
            PosterCard(
              imageUrl: d.posterUrlW500,
              title: d.title,
              metadata: isTv ? 'TV Series' : d.year,
              onTap: () => context.push(
                '/details/${isTv ? 'tv' : 'movie'}/${d.id}?poster=${Uri.encodeComponent(d.posterUrlW500)}',
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                // 48 dp: the old 24 dp square was under the touch
                // minimum and a near-miss opened the title instead.
                child: Semantics(
                  button: true,
                  label: 'Remove from watchlist',
                  child: InkWell(
                    onTap: onRemove,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
