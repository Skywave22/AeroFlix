import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

class PosterCard extends StatelessWidget {
  final String imageUrl, title;
  final String? metadata;
  final VoidCallback? onTap;
  final double width;
  const PosterCard(
      {super.key,
      required this.imageUrl,
      required this.title,
      this.metadata,
      this.onTap,
      this.width = AppSpacing.posterWidth});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.5;
    return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
            width: width,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                  borderRadius: AppRadii.mdRadius,
                  child: SizedBox(
                      width: width,
                      height: h,
                      child: imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Container(color: AppColors.surface),
                              errorWidget: (_, __, ___) => Container(
                                  color: AppColors.surface,
                                  child: const Center(
                                      child: Icon(
                                          Icons.image_not_supported_outlined,
                                          color: AppColors.textMuted,
                                          size: 28))))
                          : Container(
                              color: AppColors.surface,
                              child: const Center(
                                  child: Icon(Icons.movie_creation_outlined,
                                      color: AppColors.textMuted, size: 28))))),
              const SizedBox(height: AppSpacing.xs),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle.copyWith(fontSize: 13)),
              if (metadata != null && metadata!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(metadata!, style: AppTypography.metadata)
              ],
            ])));
  }
}
