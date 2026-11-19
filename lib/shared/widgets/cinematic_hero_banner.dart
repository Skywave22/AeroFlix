import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

class CinematicHeroBanner extends StatelessWidget {
  final String backdropUrl, title;
  final String? metadata, description;
  final VoidCallback? onPlay, onDetails, onWatchlist;
  final bool isInWatchlist;
  const CinematicHeroBanner(
      {super.key,
      required this.backdropUrl,
      required this.title,
      this.metadata,
      this.description,
      this.onPlay,
      this.onDetails,
      this.onWatchlist,
      this.isInWatchlist = false});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.58;
    return GestureDetector(
        onTap: onDetails,
        child: SizedBox(
            width: double.infinity,
            height: h,
            child: Stack(fit: StackFit.expand, children: [
              if (backdropUrl.isNotEmpty)
                CachedNetworkImage(
                    imageUrl: backdropUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (_, __) => Container(color: AppColors.surface),
                    errorWidget: (_, __, ___) =>
                        Container(color: AppColors.surface))
              else
                Container(color: AppColors.surface),
              const DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.heroScrim)),
              Positioned(
                  left: AppSpacing.horizontalPadding,
                  right: AppSpacing.horizontalPadding,
                  bottom: AppSpacing.lg,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text('FEATURED',
                                style: AppTypography.metadata.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2))),
                        const SizedBox(height: AppSpacing.sm),
                        Text(title, style: AppTypography.display),
                        if (metadata != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(metadata!, style: AppTypography.body)
                        ],
                        if (description != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(description!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body)
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        Row(children: [
                          Expanded(
                              child: _HeroButton(
                                  icon: Icons.play_arrow_rounded,
                                  label: 'Play',
                                  onTap: onPlay,
                                  filled: true)),
                          const SizedBox(width: AppSpacing.sm),
                          _HeroButton(
                              icon: isInWatchlist
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              label: 'Watchlist',
                              onTap: onWatchlist),
                          const SizedBox(width: AppSpacing.sm),
                          _HeroButton(
                              icon: Icons.info_outline,
                              label: 'Info',
                              onTap: onDetails),
                        ]),
                      ]).animate().fadeIn(duration: 600.ms).slideY(
                      begin: 0.08,
                      end: 0,
                      duration: 600.ms,
                      curve: Curves.easeOutCubic)),
            ])));
  }
}

class _HeroButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  const _HeroButton(
      {required this.icon,
      required this.label,
      this.onTap,
      this.filled = false});
  @override
  Widget build(BuildContext context) {
    final bg = filled ? AppColors.textPrimary : AppColors.overlay50,
        fg = filled ? AppColors.background : AppColors.textPrimary;
    return Material(
        color: bg,
        borderRadius: AppRadii.lgRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: filled ? AppSpacing.lg : AppSpacing.md,
                    vertical: AppSpacing.sm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: fg, size: 20),
                  const SizedBox(width: 6),
                  Text(label,
                      style: AppTypography.button
                          .copyWith(color: fg, fontSize: 14)),
                ]))));
  }
}
