import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/tmdb_service.dart';
import '../../shared/models/media_details.dart';
import '../../shared/models/watch_provider.dart';

/// "Where to Watch" — legal streaming options for a title, from TMDB's
/// JustWatch-backed /watch/providers endpoint. Tapping a provider opens the
/// JustWatch page for the title in the user's region (browser or provider
/// app), never a pirated source. Hidden entirely when no data exists.
class WatchProvidersSection extends ConsumerWidget {
  final MediaType type;
  final int id;
  const WatchProvidersSection(
      {super.key, required this.type, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
        watchProvidersProvider('${type == MediaType.tv ? 'tv' : 'movie'}:$id'));

    return async.when(
      loading: () => const _LoadingRow(),
      error: (_, __) => const SizedBox.shrink(),
      data: (providers) {
        if (providers == null || providers.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
            padding: AppSpacing.screenHorizontal,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Where to Watch', style: AppTypography.sectionHeading),
                const SizedBox(width: AppSpacing.xs),
                Text('· ${providers.region}',
                    style: AppTypography.metadata
                        .copyWith(color: AppColors.textMuted)),
              ]),
              const SizedBox(height: AppSpacing.sm),
              if (providers.flatrate.isNotEmpty)
                _Group(
                    label: 'Stream',
                    providers: providers.flatrate,
                    link: providers.link),
              if (providers.rent.isNotEmpty)
                _Group(
                    label: 'Rent',
                    providers: providers.rent,
                    link: providers.link),
              if (providers.buy.isNotEmpty)
                _Group(
                    label: 'Buy',
                    providers: providers.buy,
                    link: providers.link),
              const SizedBox(height: AppSpacing.xs),
              Text('Availability data © JustWatch, via TMDB',
                  style: AppTypography.metadata
                      .copyWith(color: AppColors.textMuted, fontSize: 10)),
            ]));
      },
    );
  }
}

class _Group extends StatelessWidget {
  final String label;
  final List<WatchProvider> providers;
  final String? link;
  const _Group({required this.label, required this.providers, this.link});

  Future<void> _open(BuildContext context) async {
    final uri = link != null ? Uri.tryParse(link!) : null;
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('Couldn\'t open the streaming page'),
              duration: Duration(seconds: 2)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('Couldn\'t open the streaming page'),
              duration: Duration(seconds: 2)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: AppTypography.metadata.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1)),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
              height: 78,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: providers.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (_, i) {
                    final p = providers[i];
                    return GestureDetector(
                        onTap: () => _open(context),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                            width: 64,
                            child: Column(children: [
                              ClipRRect(
                                  borderRadius: AppRadii.mdRadius,
                                  child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: p.logoUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: p.logoUrl,
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => Container(
                                                  color: AppColors.surface),
                                              errorWidget: (_, __, ___) =>
                                                  Container(
                                                      color: AppColors
                                                          .surfaceElevated,
                                                      child: const Icon(
                                                          Icons.tv_rounded,
                                                          color: AppColors
                                                              .textMuted,
                                                          size: 22)))
                                          : Container(
                                              color: AppColors.surfaceElevated,
                                              child: const Icon(
                                                  Icons.tv_rounded,
                                                  color: AppColors.textMuted,
                                                  size: 22)))),
                              const SizedBox(height: AppSpacing.xs),
                              Text(p.displayName,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.metadata
                                      .copyWith(fontSize: 9.5, height: 1.15)),
                            ])));
                  })),
        ]));
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: AppSpacing.screenHorizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Shimmer.fromColors(
              baseColor: AppColors.surface,
              highlightColor: AppColors.surfaceElevated,
              child: Container(
                  height: 20,
                  width: 150,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
              height: 56,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 5,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (_, __) => Shimmer.fromColors(
                      baseColor: AppColors.surface,
                      highlightColor: AppColors.surfaceElevated,
                      child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: AppRadii.mdRadius))))),
        ]));
  }
}
