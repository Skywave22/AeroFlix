import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/theme/app_colors.dart';
import '../app/theme/app_spacing.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});
  static const _tabs = <_TabDef>[
    _TabDef(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: 'Home'),
    _TabDef(
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore_rounded,
        label: 'Explore'),
    _TabDef(
        icon: Icons.search_rounded,
        activeIcon: Icons.search_rounded,
        label: 'Search'),
    _TabDef(
        icon: Icons.bookmark_border_rounded,
        activeIcon: Icons.bookmark_rounded,
        label: 'Watchlist'),
    _TabDef(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: 'Profile'),
  ];
  void _onTap(int i) => navigationShell.goBranch(i,
      initialLocation: i == navigationShell.currentIndex);
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(gradient: AppColors.navBarScrim),
        child: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
                child: BottomNavigationBar(
                    currentIndex: navigationShell.currentIndex,
                    onTap: _onTap,
                    items: [
                      for (final t in _tabs)
                        BottomNavigationBarItem(
                            icon: Icon(t.icon),
                            activeIcon: Icon(t.activeIcon),
                            label: t.label,
                            tooltip: t.label),
                    ]))),
      ));
}

class _TabDef {
  final IconData icon, activeIcon;
  final String label;
  const _TabDef(
      {required this.icon, required this.activeIcon, required this.label});
}
