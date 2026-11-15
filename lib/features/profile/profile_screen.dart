import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/cache/image_cache_provider.dart';
import '../../shared/providers/continue_watching_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/watchlist_provider.dart';
import '../downloads/downloads_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _version = '';
  String _buildNumber = '';
  int _cacheBytes = 0;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final pi = await PackageInfo.fromPlatform();
    final size = await ImageCacheService.sizeBytes();
    if (!mounted) return;
    setState(() {
      _version = pi.version;
      _buildNumber = pi.buildNumber;
      _cacheBytes = size;
    });
  }

  String _formatSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final wlCount = ref.watch(watchlistProvider).length;
    final cwCount = ref.watch(continueWatchingProvider).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.all(AppSpacing.horizontalPadding),
              physics: const BouncingScrollPhysics(),
              children: [
            // Profile header
            Row(children: [
              Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        AppColors.accent,
                        Color(0xFF7C5CFF)
                      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(36)),
                  child: const Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white, size: 36)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Welcome to AeroFlix',
                        style: AppTypography.cardTitle
                            .copyWith(fontSize: 20, letterSpacing: 0.2)),
                    const SizedBox(height: 2),
                    Text('Premium cinematic streaming',
                        style: AppTypography.metadata
                            .copyWith(color: AppColors.textMuted)),
                  ]))
            ]),
            const SizedBox(height: AppSpacing.lg),

            // Stats row
            Row(children: [
              _StatTile(
                  label: 'Watchlist',
                  value: wlCount.toString(),
                  icon: Icons.bookmark_rounded),
              const SizedBox(width: AppSpacing.md),
              _StatTile(
                  label: 'In progress',
                  value: cwCount.toString(),
                  icon: Icons.play_arrow_rounded),
            ]),
            const SizedBox(height: AppSpacing.lg),

            _SectionHeader('My Library'),
            _ListTile(
              icon: Icons.download_done_rounded,
              title: 'Downloads',
              subtitle: 'Offline saved content',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const DownloadsScreen())),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ),
            _ListTile(
              icon: Icons.history_rounded,
              title: 'Recently watched',
              subtitle: 'See your viewing history',
              onTap: () => _comingSoon('Viewing history'),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionHeader('Playback'),
            _SwitchTile(
              icon: Icons.skip_next_rounded,
              title: 'Auto-play next episode',
              subtitle: 'Continue to next episode at end credits',
              value: settings.autoPlayNext,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setAutoPlayNext(v),
            ),
            _SwitchTile(
              icon: Icons.subtitles_rounded,
              title: 'Subtitles on by default',
              subtitle: 'Turn captions on automatically',
              value: settings.subtitlesOnByDefault,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setSubtitlesOnByDefault(v),
            ),
            _ListTile(
              icon: Icons.speed_rounded,
              title: 'Default playback speed',
              subtitle:
                  '${settings.defaultSpeed.toStringAsFixed(settings.defaultSpeed.truncateToDouble() == settings.defaultSpeed ? 1 : 2)}×',
              onTap: () => _pickSpeed(settings.defaultSpeed),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionHeader('Data & Storage'),
            _SwitchTile(
              icon: Icons.signal_cellular_alt_rounded,
              title: 'Stream on cellular data',
              subtitle: 'Allow playback on mobile networks',
              value: settings.cellularAllowed,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setCellularAllowed(v),
            ),
            _ListTile(
              icon: Icons.cleaning_services_rounded,
              title: 'Clear image cache',
              subtitle: _clearing
                  ? 'Clearing…'
                  : 'Cached posters & stills: ${_formatSize(_cacheBytes)}',
              onTap: _clearing ? null : _clearCache,
            ),
            _ListTile(
              icon: Icons.delete_sweep_rounded,
              title: 'Reset all data',
              subtitle: 'Watchlist, continue watching, settings',
              onTap: _confirmReset,
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionHeader('About'),
            _ListTile(
              icon: Icons.info_outline_rounded,
              title: 'Version',
              subtitle: '$_version ($_buildNumber)',
            ),
            _ListTile(
              icon: Icons.star_outline_rounded,
              title: 'Rate AeroFlix',
              subtitle: 'Tell us what you think',
              onTap: () => _comingSoon('App rating'),
            ),
            _ListTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy & terms',
              onTap: () => _comingSoon('Privacy policy'),
            ),
            const SizedBox(height: 48),

            Center(
                child: Text('Built with ♥ for cinema fans',
                    style: AppTypography.metadata
                        .copyWith(color: AppColors.textMuted, fontSize: 11))),
            const SizedBox(height: 20),
          ])),
    );
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    await ImageCacheService.clear();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() => _clearing = false);
    _loadMeta();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Image cache cleared'),
          duration: Duration(seconds: 2)));
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape:
                  RoundedRectangleBorder(borderRadius: AppRadii.lgRadius),
              title: Text('Reset all data?',
                  style: AppTypography.cardTitle.copyWith(fontSize: 18)),
              content: Text(
                  'This will clear your watchlist, continue-watching progress, and settings. Downloads (if any) will remain.',
                  style: AppTypography.bodyPrimary
                      .copyWith(color: AppColors.textSecondary)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Cancel',
                        style: AppTypography.metadata
                            .copyWith(color: AppColors.textMuted))),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Reset',
                        style: AppTypography.metadata
                            .copyWith(color: AppColors.error))),
              ],
            ));
    if (ok != true) return;
    await ref.read(watchlistProvider.notifier).clear();
    await ref.read(continueWatchingProvider.notifier).clear();
    final p = await SharedPreferences.getInstance();
    await p.clear();
    if (!mounted) return;
    ref.invalidate(settingsProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('All data reset')));
  }

  Future<void> _pickSpeed(double current) async {
    final speeds = const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final picked = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4))),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text('Default playback speed',
                style: AppTypography.cardTitle.copyWith(fontSize: 16)),
          ),
          for (final s in speeds)
            ListTile(
              title: Text('${s.toStringAsFixed(s.truncateToDouble() == s ? 1 : 2)}×',
                  style: AppTypography.bodyPrimary.copyWith(
                      color: s == current
                          ? AppColors.accent
                          : AppColors.textPrimary,
                      fontWeight: s == current
                          ? FontWeight.w700
                          : FontWeight.w500)),
              trailing: s == current
                  ? const Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, s),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null) {
      await ref.read(settingsProvider.notifier).setDefaultSpeed(picked);
    }
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('$feature coming soon'),
          duration: const Duration(seconds: 2)));
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(
          bottom: AppSpacing.sm, top: AppSpacing.xs),
      child: Text(label,
          style:
              AppTypography.sectionHeading.copyWith(fontSize: 13, letterSpacing: 1.2)));
}

class _ListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _ListTile(
      {required this.icon,
      required this.title,
      this.subtitle,
      this.onTap,
      this.trailing});
  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.transparent,
        child: InkWell(
            borderRadius: AppRadii.lgRadius,
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm, horizontal: 4),
                child: Row(children: [
                  Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppRadii.mdRadius),
                      child: Icon(icon,
                          size: 20,
                          color: onTap == null
                              ? AppColors.textMuted
                              : AppColors.accent)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            style: AppTypography.bodyPrimary.copyWith(
                                fontWeight: FontWeight.w600,
                                color: onTap == null
                                    ? AppColors.textMuted
                                    : AppColors.textPrimary)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!,
                              style: AppTypography.metadata.copyWith(
                                  color: AppColors.textMuted, fontSize: 12)),
                        ]
                      ])),
                  if (trailing != null) trailing!,
                ]))));
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile(
      {required this.icon,
      required this.title,
      this.subtitle,
      required this.value,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => _ListTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        activeColor: AppColors.accent,
        inactiveThumbColor: AppColors.textMuted,
        inactiveTrackColor: AppColors.surfaceElevated,
        trackOutlineWidth: const WidgetStatePropertyAll(0),
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value));
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatTile(
      {required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Expanded(
      child: Container(
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md, horizontal: AppSpacing.md),
          decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: AppRadii.mdRadius),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: AppRadii.smRadius),
                child: Icon(icon, color: AppColors.accent, size: 20)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(value,
                      style: AppTypography.cardTitle.copyWith(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(label,
                      style: AppTypography.metadata.copyWith(
                          color: AppColors.textMuted, fontSize: 11)),
                ]))
          ])));
}
