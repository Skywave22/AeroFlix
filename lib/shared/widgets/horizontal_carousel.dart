import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

class HorizontalCarousel extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height, itemSpacing;
  final EdgeInsets padding;
  const HorizontalCarousel(
      {super.key,
      required this.title,
      required this.itemCount,
      required this.itemBuilder,
      this.onSeeAll,
      this.height = 260,
      this.itemSpacing = AppSpacing.md,
      this.padding = const EdgeInsets.symmetric(
          horizontal: AppSpacing.horizontalPadding)});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: padding,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: AppTypography.sectionHeading),
                  if (onSeeAll != null)
                    TextButton(
                        onPressed: onSeeAll,
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('See all',
                              style: AppTypography.metadata
                                  .copyWith(color: AppColors.textSecondary)),
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right,
                              size: 16, color: AppColors.textSecondary),
                        ])),
                ])),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
            height: height,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: padding,
                physics: const BouncingScrollPhysics(),
                itemCount: itemCount,
                separatorBuilder: (_, __) => SizedBox(width: itemSpacing),
                itemBuilder: itemBuilder)),
      ]);
}
