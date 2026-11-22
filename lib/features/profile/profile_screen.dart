import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tj_flutter_providers/tj_providers.dart' show ProvidersScreen;

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/cache/image_cache_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/tj_providers_service.dart';
import '../../shared/models/media_details.dart';
import '../../shared/providers/continue_watching_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/watchlist_provider.dart';
import '../../features/providers/provider_diagnostics_screen.dart';
import 'about_sheet.dart';

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
    final status = ref.watch(providerStatusProvider);
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
            Row(
              children: [
                Image.asset(
                  'assets/images/logo_mark.png',
                  width: 72,
                  height: 72,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome to AeroFlix',
                        style: AppTypography.cardTitle.copyWith(
                          fontSize: 20,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Premium cinematic streaming',
                        style: AppTypography.metadata.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Stats row
            Row(
              children: [
                _StatTile(
                  label: 'Watchlist',
                  value: wlCount.toString(),
                  icon: Icons.bookmark_rounded,
                ),
                const SizedBox(width: AppSpacing.md),
                _StatTile(
                  label: 'In progress',
                  value: cwCount.toString(),
                  icon: Icons.play_arrow_rounded,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionHeader('My Library'),
            _ListTile(
              icon: Icons.download_done_rounded,
              title: 'Downloads',
              subtitle: 'Offline saved content',
              onTap: () => context.push('/downloads'),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ),
            _ListTile(
              icon: Icons.history_rounded,
              title: 'Recently watched',
              subtitle: cwCount == 0
                  ? 'Nothing watched yet'
                  : '$cwCount title${cwCount == 1 ? '' : 's'} in progress',
              onTap: cwCount == 0 ? null : _showHistory,
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ),
            _ListTile(
              icon: Icons.extension_rounded,
              title: 'Providers',
              subtitle: status.busy
                  ? status.summary
                  : '${status.installed} sources · ${status.updated} updated',
              onTap: _openProviders,
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ),
            _ListTile(
              icon: Icons.monitor_heart_outlined,
              title: 'Provider status',
              subtitle: status.error != null
                  ? 'Offline copy in use — tap for details'
                  : (status.syncedAt == null
                      ? 'Not checked yet'
                      : 'Checked ${_ago(status.syncedAt!)}'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProviderDiagnosticsScreen(),
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
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
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
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
              icon: Icons.numbers_rounded,
              title: 'Version',
              subtitle: 'AeroFlix $_version (build $_buildNumber)',
            ),
            _ListTile(
              icon: Icons.ios_share_rounded,
              title: 'Share AeroFlix',
              subtitle: 'Send the app to a friend',
              onTap: _shareApp,
            ),
            _ListTile(
              icon: Icons.privacy_tip_outlined,
              title: 'About, privacy & terms',
              subtitle: 'What this app does and what it stores',
              onTap: () => AboutSheet.show(
                context,
                version: _version,
                build: _buildNumber,
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Center(
              child: Text(
                'Built with ♥ for cinema fans',
                style: AppTypography.metadata.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
            SizedBox(height: 20 + MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
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
      ..showSnackBar(
        const SnackBar(
          content: Text('Image cache cleared'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.lgRadius),
        title: Text(
          'Reset all data?',
          style: AppTypography.cardTitle.copyWith(fontSize: 18),
        ),
        content: Text(
          'This will clear your watchlist, continue-watching progress, and settings. Downloads (if any) will remain.',
          style: AppTypography.bodyPrimary.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTypography.metadata.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Reset',
              style: AppTypography.metadata.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(watchlistProvider.notifier).clear();
    await ref.read(continueWatchingProvider.notifier).clear();
    // Clear only the keys this app owns — never a blanket prefs.clear(),
    // which would silently wipe the downloads index too.
    final p = await SharedPreferences.getInstance();
    final keysToRemove = p.getKeys().where((k) {
      return k == AppConstants.prefWatchlist ||
          k == AppConstants.prefContinueWatching ||
          k == AppConstants.prefRecentSearches ||
          k == AppConstants.prefPreferredQuality ||
          k.startsWith('settings.');
    }).toList();
    for (final k in keysToRemove) {
      await p.remove(k);
    }
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
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.sheetRadius),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Default playback speed',
                style: AppTypography.cardTitle.copyWith(fontSize: 16),
              ),
            ),
            for (final s in speeds)
              ListTile(
                title: Text(
                  '${s.toStringAsFixed(s.truncateToDouble() == s ? 1 : 2)}×',
                  style: AppTypography.bodyPrimary.copyWith(
                    color:
                        s == current ? AppColors.accent : AppColors.textPrimary,
                    fontWeight:
                        s == current ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: s == current
                    ? const Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref.read(settingsProvider.notifier).setDefaultSpeed(picked);
    }
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  void _openProviders() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProvidersScreen(
          service: ref.read(providerServiceProvider),
          initialEnabled: ref.read(enabledProviderIdsProvider),
          onEnabledChanged: (ids) {
            final notifier = ref.read(enabledProviderIdsProvider.notifier);
            for (final id in ids) {
              notifier.setEnabled(id, true);
            }
            for (final id in ref
                .read(enabledProviderIdsProvider)
                .where((id) => !ids.contains(id))
                .toList()) {
              notifier.setEnabled(id, false);
            }
            ref.invalidate(providerServiceProvider);
          },
        ),
      ),
    );
  }

  Future<void> _shareApp() async {
    // Share.share reports the outcome; it used to `hideCurrentSnackBar()`
    // without ever showing one, which is a no-op that reads like feedback.
    final result = await Share.share(
      'AeroFlix — movies, series and anime with real sources. '
      'https://github.com/Skywave22/AeroFlix',
      subject: 'AeroFlix',
    );
    if (!mounted) return;
    if (result.status == ShareResultStatus.unavailable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No app available to share with'),
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  /// Real viewing history, built from the continue-watching store.
  void _showHistory() {
    final items = [...ref.read(continueWatchingProvider)]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, controller) => ListView.builder(
          controller: controller,
          padding: const EdgeInsets.all(AppSpacing.horizontalPadding),
          itemCount: items.length + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'Recently watched',
                  style: AppTypography.sectionHeading,
                ),
              );
            }
            final it = items[i - 1];
            final pct = (it.progress * 100).round();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(it.title, style: AppTypography.cardTitle),
              subtitle: Text(
                it.type == MediaType.tv
                    ? 'S${it.season.toString().padLeft(2, '0')}E${it.episode.toString().padLeft(2, '0')}'
                        '${it.episodeTitle != null ? ' · ${it.episodeTitle}' : ''} · $pct% watched'
                    : '$pct% watched',
                style: AppTypography.caption,
              ),
              trailing: const Icon(Icons.play_arrow_rounded),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/details/${it.type.name}/${it.id}');
              },
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.xs),
        child: Text(
          label,
          style: AppTypography.sectionHeading.copyWith(
            fontSize: 13,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _ListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _ListTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.lgRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: 4,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.mdRadius,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: onTap == null ? AppColors.textMuted : AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyPrimary.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onTap == null
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppTypography.metadata.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => _ListTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: Switch(
          value: value,
          activeThumbColor: AppColors.accent,
          inactiveThumbColor: AppColors.textMuted,
          inactiveTrackColor: AppColors.surfaceElevated,
          trackOutlineWidth: const WidgetStatePropertyAll(0),
          onChanged: onChanged,
        ),
        onTap: () => onChanged(!value),
      );
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.mdRadius,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadii.smRadius,
                ),
                child: Icon(icon, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: AppTypography.cardTitle.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      label,
                      style: AppTypography.metadata.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
