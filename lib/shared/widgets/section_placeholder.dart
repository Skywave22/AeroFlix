import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

class SectionLoadingPlaceholder extends StatelessWidget {
  final int count;
  final double posterWidth;
  const SectionLoadingPlaceholder(
      {super.key, this.count = 6, this.posterWidth = AppSpacing.posterWidth});
  @override
  Widget build(BuildContext context) {
    final h = posterWidth * 1.5;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: AppSpacing.screenHorizontal,
          child: Shimmer.fromColors(
              baseColor: AppColors.surface,
              highlightColor: AppColors.surfaceElevated,
              child: Container(
                  height: 22,
                  width: 160,
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: AppRadii.smRadius)))),
      const SizedBox(height: AppSpacing.sm),
      SizedBox(
          height: h + 32,
          child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: AppSpacing.screenHorizontal,
              itemCount: count,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (_, __) => Shimmer.fromColors(
                  baseColor: AppColors.surface,
                  highlightColor: AppColors.surfaceElevated,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            width: posterWidth,
                            height: h,
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: AppRadii.mdRadius)),
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                            width: posterWidth * 0.8,
                            height: 12,
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: AppRadii.smRadius)),
                      ])))),
    ]);
  }
}

class SectionErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const SectionErrorState({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 32),
        const SizedBox(height: AppSpacing.sm),
        Text(message, style: AppTypography.body, textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'))
        ],
      ]));
}

class SectionEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const SectionEmptyState(
      {super.key, required this.message, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: AppColors.textMuted, size: 40),
        const SizedBox(height: AppSpacing.sm),
        Text(message, style: AppTypography.body, textAlign: TextAlign.center),
      ]));
}
