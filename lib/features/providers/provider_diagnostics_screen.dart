import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tj_flutter_providers/tj_providers.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/providers/tj_providers_service.dart';

/// Everything that can go wrong between the app and a playable link, on one
/// screen: bundled-seed status, GitHub sync result, cached provider versions
/// and a live "run every provider" test.
class ProviderDiagnosticsScreen extends ConsumerStatefulWidget {
  const ProviderDiagnosticsScreen({super.key});

  @override
  ConsumerState<ProviderDiagnosticsScreen> createState() =>
      _ProviderDiagnosticsScreenState();
}

class _ProviderDiagnosticsScreenState
    extends ConsumerState<ProviderDiagnosticsScreen> {
  final Map<String, ProviderOutcome> _results = {};
  bool _running = false;
  String? _runningId;

  Future<void> _runTests() async {
    final service = ref.read(providerServiceProvider);
    setState(() {
      _running = true;
      _results.clear();
    });
    for (final id in service.enabledIds) {
      if (!mounted) return;
      setState(() => _runningId = id);
      final outcome = await service.testProvider(
        id,
        timeout: const Duration(seconds: 40),
      );
      if (!mounted) return;
      setState(() => _results[id] = outcome);
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _runningId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(providerStatusProvider);
    final cached = ref.watch(installedProvidersProvider);
    // Watch so a toggle / sync rebuild updates the ids shown below.
    final service = ref.watch(providerServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text('Provider status', style: AppTypography.cardTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _Card(
            title: 'Sync',
            rows: [
              _Row('State', status.phase.name),
              _Row('Summary', status.summary),
              _Row('Bundled seed', '${status.seeded} installed from APK'),
              _Row('Providers on device', '${status.installed}'),
              _Row('Enabled for playback', '${service.enabledIds.join(', ')}'),
              _Row('Mirror', status.mirror ?? '—'),
              _Row(
                'Last check',
                status.syncedAt?.toLocal().toString().split('.').first ?? '—',
              ),
              if (status.error != null) _Row('Network error', status.error!),
            ],
            action: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: status.busy
                        ? null
                        : () => ref
                              .read(providerStatusProvider.notifier)
                              .refresh(),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: Text(status.busy ? 'Checking…' : 'Check GitHub now'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(enabledProviderIdsProvider.notifier)
                          .reset();
                      ref.invalidate(providerServiceProvider);
                    },
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reset to recommended providers'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProvidersScreen(
                          service: ref.read(providerServiceProvider),
                          initialEnabled: ref.read(enabledProviderIdsProvider),
                          // Persist toggles and rebuild the service so the
                          // change reaches the next stream request.
                          onEnabledChanged: (ids) async {
                            final notifier = ref.read(
                              enabledProviderIdsProvider.notifier,
                            );
                            for (final id in ids) {
                              await notifier.setEnabled(id, true);
                            }
                            for (final id
                                in ref
                                    .read(enabledProviderIdsProvider)
                                    .where((id) => !ids.contains(id))
                                    .toList()) {
                              await notifier.setEnabled(id, false);
                            }
                            ref.invalidate(providerServiceProvider);
                          },
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.extension_rounded, size: 18),
                    label: const Text('Manage providers'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Card(
            title: 'Installed providers',
            rows: cached.when(
              loading: () => const [_Row('', 'reading device…')],
              error: (e, _) => [_Row('error', '$e')],
              data: (map) {
                if (map.isEmpty) {
                  return const [
                    _Row('', 'none yet — check GitHub or relaunch'),
                  ];
                }
                final enabled = service.enabledIds;
                return [
                  for (final entry
                      in (map.entries.toList()
                        ..sort((a, b) => a.key.compareTo(b.key))))
                    _Row(
                      '${entry.key}${enabled.contains(entry.key) ? '  ✓' : ''}',
                      'v${entry.value.version} · '
                          '${(entry.value.sizeBytes / 1024).round()} KB',
                    ),
                ];
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Card(
            title: 'Live test (TMDB 550 · Fight Club)',
            rows: [
              for (final id in service.enabledIds)
                _Row(
                  id,
                  _results[id] == null
                      ? (_runningId == id ? 'running…' : '—')
                      : _results[id]!.ok
                      ? '${_results[id]!.count} links in '
                            '${_results[id]!.elapsed.inSeconds}s'
                      : 'failed: ${_results[id]!.error}',
                ),
            ],
            action: FilledButton.icon(
              onPressed: _running ? null : _runTests,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(_running ? 'Testing…' : 'Run test'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'A provider that fails here is broken upstream, not in AeroFlix. '
            'Open Plugins to update it, or wait for the next auto-update.',
            style: AppTypography.bodyPrimary.copyWith(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.rows, this.action});
  final String title;
  final List<Widget> rows;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.mdRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.sectionHeading),
          const SizedBox(height: 10),
          ...rows,
          if (action != null) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: action),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodyPrimary.copyWith(
      color: AppColors.textSecondary,
      fontSize: 12,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: style.copyWith(color: AppColors.textMuted),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}
