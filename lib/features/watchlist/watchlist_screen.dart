import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
          child: Padding(
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
                          Text('Tap the bookmark icon on any title to save it.',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)),
                        ]))),
                  ]))));
}
