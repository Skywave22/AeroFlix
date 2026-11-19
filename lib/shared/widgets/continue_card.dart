import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/api_constants.dart';
import '../providers/continue_watching_provider.dart';

class ContinueCard extends StatelessWidget {
  final ContinueWatchingItem item;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final double width;
  const ContinueCard({
    super.key,
    required this.item,
    this.onTap,
    this.onRemove,
    this.width = 220,
  });

  @override
  Widget build(BuildContext context) {
    final image = item.backdropPath != null
        ? ApiConstants.backdropUrl(
            item.backdropPath!,
            size: ApiConstants.backdropSizeW780,
          )
        : (item.posterPath != null
            ? ApiConstants.posterUrl(item.posterPath!)
            : '');
    final label = item.season > 0
        ? 'S${item.season.toString().padLeft(2, '0')}E${item.episode.toString().padLeft(2, '0')}'
        : 'Movie';
    final sub = item.episodeTitle != null && item.episodeTitle!.isNotEmpty
        ? item.episodeTitle!
        : item.title;
    return Semantics(
      button: true,
      label:
          '${item.title}, $label, ${(item.progress * 100).round()} percent watched',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: AppRadii.mdRadius,
                    child: SizedBox(
                      width: width,
                      height: width * 9 / 16,
                      child: image.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: image,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Container(color: AppColors.surfaceElevated),
                              errorWidget: (_, __, ___) => Container(
                                color: AppColors.surfaceElevated,
                                child: const Center(
                                  child: Icon(
                                    Icons.play_circle_fill,
                                    color: AppColors.textMuted,
                                    size: 48,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.surfaceElevated,
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  color: AppColors.textMuted,
                                  size: 48,
                                ),
                              ),
                            ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.mdRadius,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: Center(
                      child: Icon(
                        Icons.play_circle_filled_rounded,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
                  ),
                  if (onRemove != null)
                    // 48 dp target, inside a dark circle so it stays visible over a
                    // bright still. The old 28 dp square was under the touch
                    // minimum and a near-miss opened the title instead.
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Semantics(
                        button: true,
                        label: 'Remove ${item.title} from Continue Watching',
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onRemove,
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(AppRadii.md),
                      ),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.cardTitle.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
