import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text('Downloads', style: AppTypography.title),
        elevation: 0,
      ),
      body: Center(
          child: Padding(
              padding:
                  const EdgeInsets.all(AppSpacing.horizontalPadding),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(50)),
                        child: const Icon(Icons.download_outlined,
                            color: AppColors.textMuted, size: 48)),
                    const SizedBox(height: AppSpacing.lg),
                    Text('No downloads yet',
                        style: AppTypography.title.copyWith(fontSize: 18)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                        'Movies and shows you save for offline viewing will appear here.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyPrimary
                            .copyWith(color: AppColors.textMuted)),
                  ]))));
}
