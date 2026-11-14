import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/app_constants.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
          child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.horizontalPadding),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    Text('Profile', style: AppTypography.screenHeading),
                    const SizedBox(height: AppSpacing.xl),
                    Center(
                        child: Column(children: [
                      Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(44),
                              border: Border.all(
                                  color: AppColors.outline, width: 1)),
                          child: const Icon(Icons.person_rounded,
                              size: 40, color: AppColors.textMuted)),
                      const SizedBox(height: AppSpacing.md),
                      Text('Guest', style: AppTypography.sectionHeading),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Sign in later to sync watchlist across devices',
                          style: AppTypography.metadata),
                    ])),
                    const SizedBox(height: AppSpacing.xxl),
                    _tile(Icons.history_rounded, 'Viewing history', () {}),
                    _tile(Icons.settings_outlined, 'Settings', () {}),
                    _tile(Icons.help_outline, 'Help & About', () {}),
                    const SizedBox(height: AppSpacing.xxl),
                    Center(
                        child: Text(
                            '${AppConstants.appName} v${AppConstants.appVersion} · Preview build',
                            style: AppTypography.metadata)),
                    const SizedBox(height: AppSpacing.xl),
                  ]))));
  Widget _tile(IconData i, String l, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
          color: AppColors.surface,
          borderRadius: AppRadii.mdRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: onTap,
              child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(children: [
                    Icon(i, size: 22, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                        child: Text(l,
                            style: AppTypography.cardTitle
                                .copyWith(fontSize: 15))),
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: AppColors.textMuted),
                  ])))));
}
