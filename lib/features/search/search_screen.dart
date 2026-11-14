import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

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
                    const SizedBox(height: AppSpacing.md),
                    Text('Search', style: AppTypography.screenHeading),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                        controller: _c,
                        autofocus: true,
                        style: AppTypography.bodyPrimary,
                        decoration: InputDecoration(
                            hintText: 'Movies, shows, actors…',
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: AppColors.textMuted),
                            suffixIcon: _c.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear,
                                        color: AppColors.textMuted, size: 20),
                                    onPressed: () => setState(() => _c.clear()))
                                : null),
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: AppSpacing.xl),
                    Text('Recent searches',
                        style: AppTypography.sectionHeading
                            .copyWith(fontSize: 16)),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final t in const [
                            'Dune 2',
                            'Stranger Things',
                            'Anime',
                            'Bollywood'
                          ])
                            Chip(
                                label: Text(t),
                                backgroundColor: AppColors.surface,
                                labelStyle: AppTypography.metadata
                                    .copyWith(color: AppColors.textSecondary),
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(
                                    borderRadius: AppRadii.smRadius)),
                        ]),
                    const Spacer(),
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(AppSpacing.xl),
                            child: Text('Search results appear as you type.',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 13),
                                textAlign: TextAlign.center))),
                    const SizedBox(height: 40),
                  ]))));
}
