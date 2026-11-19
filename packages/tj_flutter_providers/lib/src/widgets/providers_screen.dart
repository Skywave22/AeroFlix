import 'package:flutter/material.dart';

import '../models.dart';
import '../provider_service.dart';

/// Drop-in Providers screen: list, enable/disable, update button, version badges.
///
/// Add to your app:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => ProvidersScreen(service: service),
/// ));
/// ```
class ProvidersScreen extends StatefulWidget {
  final ProviderService service;

  /// Called with the new enabled set whenever a switch changes.
  ///
  /// The widget used to hold the set in local state only: the switches looked
  /// live but the service kept its constructor list, so toggling a provider
  /// had no effect on playback and the selection was lost on the next visit.
  final ValueChanged<Set<String>>? onEnabledChanged;

  /// Seed for the switches. Defaults to `service.enabledIds`.
  final Set<String>? initialEnabled;

  const ProvidersScreen({
    super.key,
    required this.service,
    this.onEnabledChanged,
    this.initialEnabled,
  });

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  UpdateCheckResult? _result;
  Map<String, CachedProvider> _cached = {};
  bool _loading = true;
  bool _updating = false;
  String? _error;
  Set<String> _enabled = {};

  @override
  void initState() {
    super.initState();
    _enabled = (widget.initialEnabled ?? widget.service.enabledIds).toSet();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _cached = await widget.service.manager.getCached();
      _result = await widget.service.manager.checkForUpdates();
    } catch (e) {
      _error = e.toString();
      // Offline fallback: show cached manifest
      final cachedManifest = await widget.service.manager.getCachedManifest();
      if (cachedManifest != null) {
        _result = UpdateCheckResult(
          manifest: cachedManifest,
          available: const [],
          updatesAvailable: const [],
          upToDate: cachedManifest.scrapers,
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _updateAll() async {
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      await widget.service.checkAndUpdate();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Providers updated')));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _updating = false);
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _result?.manifest;
    final providers = manifest?.scrapers ?? [];
    final updates = _result?.updatesAvailable.map((e) => e.id).toSet() ?? {};
    final available = _result?.available.map((e) => e.id).toSet() ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Providers'),
        actions: [
          IconButton(
            icon: _updating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Check for updates',
            onPressed: _updating ? null : _updateAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  if (_error != null)
                    ListTile(
                      leading: const Icon(
                        Icons.error_outline,
                        color: Colors.orange,
                      ),
                      title: Text(
                        'Could not reach GitHub — showing cached providers',
                      ),
                      subtitle: Text(
                        _error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (manifest != null)
                    ListTile(
                      title: Text('${manifest.name} v${manifest.version}'),
                      subtitle: Text(
                        '${providers.length} providers · ${updates.length} update(s) available · ${available.length} not downloaded',
                      ),
                      trailing: (updates.isNotEmpty || available.isNotEmpty)
                          ? FilledButton(
                              onPressed: _updating ? null : _updateAll,
                              child: const Text('Update'),
                            )
                          : const Chip(label: Text('Up to date')),
                    ),
                  if (providers.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No providers in the manifest yet. Pull down to retry.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const Divider(),
                  ...providers.map(
                    (p) => _tile(
                      p,
                      updates.contains(p.id),
                      available.contains(p.id),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _tile(ProviderInfo p, bool hasUpdate, bool notDownloaded) {
    final cached = _cached[p.id];
    final isEnabled = _enabled.contains(p.id);
    final status = notDownloaded
        ? 'Not downloaded'
        : hasUpdate
        ? 'Update available: v${cached?.version} → v${p.version}'
        : 'v${p.version}';

    return ListTile(
      leading: p.logo != null
          ? Image.network(
              p.logo!,
              width: 36,
              height: 36,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.play_circle_outline),
            )
          : const Icon(Icons.play_circle_outline),
      title: Text(p.name),
      subtitle: Text(
        '$status\n${p.description}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Semantics(
        label: '${p.name} enabled',
        child: Switch(
          value: isEnabled,
          // The last enabled provider cannot be switched off: with none left,
          // every title would fail to resolve with no explanation.
          onChanged: (_enabled.length == 1 && isEnabled)
              ? null
              : (v) {
                  setState(() {
                    if (v) {
                      _enabled.add(p.id);
                    } else {
                      _enabled.remove(p.id);
                    }
                  });
                  widget.service.setEnabledIds(_enabled);
                  widget.onEnabledChanged?.call(Set.unmodifiable(_enabled));
                },
        ),
      ),
      onTap: () async {
        if (notDownloaded || hasUpdate) {
          setState(() => _updating = true);
          try {
            await widget.service.manager.downloadProvider(p);
            await _load();
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(e.toString())));
            }
          }
          if (mounted) setState(() => _updating = false);
        }
      },
    );
  }
}
