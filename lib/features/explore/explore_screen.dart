import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../shared/widgets/category_chip.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  static const _cats = [
    'All',
    'Action',
    'Comedy',
    'Drama',
    'Horror',
    'Sci-Fi',
    'Thriller',
    'Romance',
    'Animation',
    'Documentary',
    'Bollywood',
    'Anime'
  ];
  String _sel = 'All';
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
          child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
            SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.horizontalPadding,
                        AppSpacing.lg,
                        AppSpacing.horizontalPadding,
                        AppSpacing.md),
                    child:
                        Text('Explore', style: AppTypography.screenHeading))),
            SliverToBoxAdapter(
                child: SizedBox(
                    height: 44,
                    child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.horizontalPadding),
                        itemCount: _cats.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.xs),
                        itemBuilder: (_, i) => CategoryChip(
                            label: _cats[i],
                            selected: _sel == _cats[i],
                            onTap: () => setState(() => _sel = _cats[i]))))),
            const SliverToBoxAdapter(
                child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.grid_view_rounded,
                          size: 56, color: AppColors.textMuted),
                      SizedBox(height: AppSpacing.md),
                      Text('Poster grid coming next',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: AppSpacing.sm),
                      Text(
                          'Genre filtering and sort options land with Phase 1 details.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                          textAlign: TextAlign.center),
                    ])))),
          ])));
}
