import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/theme/app_colors.dart';
import '../app/theme/app_spacing.dart';
import '../shared/providers/watchlist_provider.dart';

class AppShell extends ConsumerWidget {
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
        label: 'Watchlist',
        showBadge: true),
    _TabDef(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: 'Profile'),
  ];
  void _onTap(int i) => navigationShell.goBranch(i,
      initialLocation: i == navigationShell.currentIndex);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wlCount = ref.watch(watchlistProvider).length;
    return Scaffold(
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
                        for (var i = 0; i < _tabs.length; i++)
                          _buildItem(_tabs[i],
                              count: _tabs[i].showBadge ? wlCount : 0),
                      ]))),
        ));
  }

  BottomNavigationBarItem _buildItem(_TabDef t, {int count = 0}) {
    final icon = Icon(t.icon);
    final active = Icon(t.activeIcon);
    if (count <= 0) {
      return BottomNavigationBarItem(
          icon: icon, activeIcon: active, label: t.label, tooltip: t.label);
    }
    return BottomNavigationBarItem(
        icon: Stack(clipBehavior: Clip.none, children: [
          icon,
          Positioned(
              right: -8,
              top: -4,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10)),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700))))
        ]),
        activeIcon: Stack(clipBehavior: Clip.none, children: [
          active,
          Positioned(
              right: -8,
              top: -4,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10)),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700))))
        ]),
        label: t.label,
        tooltip: t.label);
  }
}

class _TabDef {
  final IconData icon, activeIcon;
  final String label;
  final bool showBadge;
  const _TabDef(
      {required this.icon,
      required this.activeIcon,
      required this.label,
      this.showBadge = false});
}
