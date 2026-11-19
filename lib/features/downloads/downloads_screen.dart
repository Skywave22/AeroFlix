import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/api_constants.dart';
import '../../shared/models/media_details.dart';
import '../../shared/providers/download_provider.dart';
import '../../shared/providers/stream_providers.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});
  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  /// Multi-select mode. The app bar used to say "Edit" and then toast
  /// "Swipe items to delete" — a label that did nothing. Now it really edits.
  bool _editing = false;
  final Set<String> _selected = {};

  void _exitEdit() => setState(() {
    _editing = false;
    _selected.clear();
  });

  void _toggle(String key) => setState(() {
    if (!_selected.remove(key)) _selected.add(key);
  });

  Future<void> _deleteSelected() async {
    final keys = _selected.toList();
    final ok = await _confirm(
      title: keys.length == 1
          ? 'Delete download?'
          : 'Delete ${keys.length} downloads?',
      body: 'The downloaded video files will be removed from this device.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    final n = ref.read(downloadProvider.notifier);
    for (final k in keys) {
      await n.remove(k);
    }
    if (mounted) _exitEdit();
  }

  Future<void> _clearCompleted() async {
    final ok = await _confirm(
      title: 'Clear finished downloads?',
      body: 'Completed downloads will be removed. In-progress downloads are kept.',
      action: 'Clear',
    );
    if (!ok || !mounted) return;
    await ref.read(downloadProvider.notifier).clearCompleted();
    if (mounted) _exitEdit();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(downloadProvider);
    final hasCompleted = items.any((d) => d.status == DownloadStatus.completed);
    final hasPaused = items.any((d) => d.status == DownloadStatus.paused);

    // Leave edit mode automatically if the list empties out.
    if (_editing && items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editing) _exitEdit();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: _editing
            ? IconButton(
                tooltip: 'Cancel selection',
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitEdit,
              )
            : null,
        title: Text(
          _editing ? '${_selected.length} selected' : 'Downloads',
          style: AppTypography.cardTitle,
        ),
        actions: [
          if (items.isNotEmpty && !_editing)
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: Text(
                'Edit',
                style: AppTypography.metadata.copyWith(color: AppColors.accent),
              ),
            ),
          if (items.isNotEmpty && _editing)
            IconButton(
              tooltip: 'Select all',
              icon: Icon(
                _selected.length == items.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
              onPressed: () => setState(() {
                if (_selected.length == items.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(items.map((d) => d.key));
                }
              }),
            ),
          if (hasPaused && _editing)
            IconButton(
              tooltip: 'Resume paused downloads',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () {
                final n = ref.read(downloadProvider.notifier);
                for (final d in items.where(
                  (d) => d.status == DownloadStatus.paused,
                )) {
                  n.resume(d.key);
                }
                _exitEdit();
              },
            ),
          if (hasCompleted && _editing)
            IconButton(
              tooltip: 'Clear finished downloads',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: _clearCompleted,
            ),
          if (_editing)
            IconButton(
              tooltip: 'Delete selected',
              icon: Icon(
                Icons.delete_outline,
                color: _selected.isEmpty
                    ? AppColors.textMuted
                    : AppColors.error,
              ),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: items.isEmpty
          ? _emptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.horizontalPadding),
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final item = items[i];
                return _DownloadRow(
                  item: item,
                  editing: _editing,
                  selected: _selected.contains(item.key),
                  onToggleSelected: () => _toggle(item.key),
                );
              },
            ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.horizontalPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.download_outlined,
              color: AppColors.textMuted,
              size: 48,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No downloads yet',
            style: AppTypography.cardTitle.copyWith(fontSize: 18),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap the download icon on any movie or episode to save it for offline viewing.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => context.go('/explore'),
            icon: const Icon(Icons.explore_outlined, size: 18),
            label: const Text('Browse titles'),
          ),
        ],
      ),
    ),
  );
}

class _DownloadRow extends ConsumerWidget {
  final DownloadItem item;
  final bool editing;
  final bool selected;
  final VoidCallback onToggleSelected;
  const _DownloadRow({
    required this.item,
    required this.editing,
    required this.selected,
    required this.onToggleSelected,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poster = item.posterPath != null
        ? ApiConstants.posterUrl(item.posterPath)
        : '';
    final isDone = item.status == DownloadStatus.completed;
    final isActive = item.status == DownloadStatus.downloading;
    final row = _row(context, ref, poster, isDone, isActive);
    if (editing) {
      // In edit mode the whole row is a checkbox: swiping to delete and
      // tapping play/settings at the same time is how downloads got lost.
      return Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: InkWell(
          borderRadius: AppRadii.mdRadius,
          onTap: onToggleSelected,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadii.mdRadius,
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelected(),
                  ),
                ),
                Expanded(child: IgnorePointer(child: row)),
              ],
            ),
          ),
        ),
      );
    }
    return Dismissible(
      key: ValueKey(item.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: AppRadii.mdRadius,
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => ref.read(downloadProvider.notifier).remove(item.key),
      child: _row(context, ref, poster, isDone, isActive),
    );

    Widget _row(
      BuildContext context,
      WidgetRef ref,
      String poster,
      bool isDone,
      bool isActive,
    ) => Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.mdRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadii.smRadius,
            child: SizedBox(
              width: 88,
              height: 56,
              child: poster.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: AppColors.surfaceElevated),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceElevated,
                        child: const Icon(
                          Icons.movie,
                          color: AppColors.textMuted,
                          size: 22,
                        ),
                      ),
                    )
                  : Container(
                      color: AppColors.surfaceElevated,
                      child: const Icon(
                        Icons.movie,
                        color: AppColors.textMuted,
                        size: 22,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyPrimary.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata.copyWith(
                    color: isDone
                        ? AppColors.success
                        : (isActive ? AppColors.accent : AppColors.textMuted),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: isDone
                        ? 1
                        : (item.status == DownloadStatus.paused ||
                                  item.status == DownloadStatus.failed
                              ? item.progress
                              : null),
                    minHeight: 3,
                    backgroundColor: AppColors.surfaceElevated,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDone
                          ? AppColors.success
                          : (item.status == DownloadStatus.failed
                                ? AppColors.error
                                : AppColors.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _trailing(context, ref),
        ],
      ),
    );
  }

  String _subtitle() {
    switch (item.status) {
      case DownloadStatus.completed:
        return 'Downloaded${item.sizeLabel.isNotEmpty ? ' · ${item.sizeLabel}' : ''}';
      case DownloadStatus.downloading:
        return 'Downloading · ${(item.progress * 100).toStringAsFixed(0)}%';
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.paused:
        return 'Paused · ${(item.progress * 100).toStringAsFixed(0)}%';
      case DownloadStatus.failed:
        return item.error == null
            ? 'Failed — tap the retry button'
            : 'Failed: ${item.error!.length > 60 ? '${item.error!.substring(0, 60)}…' : item.error!}';
    }
  }

  /// Re-resolve a direct-file source for a failed item, then restart it.
  Future<void> _retryWithFreshSource(
    BuildContext context,
    WidgetRef ref,
    DownloadNotifier n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final details = MediaDetails(
      type: item.kind == 'tv' ? MediaType.tv : MediaType.movie,
      id: item.mediaId,
      title: item.title,
      posterPath: item.posterPath,
    );
    String? url;
    Map<String, String> headers = const {};
    try {
      final sources = await ref
          .read(streamServiceProvider)
          .getAllStreams(details, season: item.season, episode: item.episode);
      for (final s in sources) {
        final u = s.url.toLowerCase();
        if (u.contains('.mp4') || u.contains('.mkv')) {
          url = s.url;
          headers = s.headers;
          break;
        }
      }
    } catch (_) {
      url = null;
    }
    if (url == null) {
      await n.retry(item.key); // no better link available: retry as-is
      return;
    }
    await n.rearm(item.key, url, headers: headers);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Retrying with a fresh source link'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Widget _trailing(BuildContext context, WidgetRef ref) {
    final n = ref.read(downloadProvider.notifier);
    switch (item.status) {
      case DownloadStatus.completed:
        return IconButton(
          tooltip: 'Play offline',
          icon: const Icon(
            Icons.play_arrow_rounded,
            color: AppColors.accent,
            size: 26,
          ),
          onPressed: () {
            final fp = item.filePath;
            if (fp == null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('This download is missing its file'),
                    duration: Duration(seconds: 2),
                  ),
                );
              return;
            }
            final details = MediaDetails(
              type: item.kind == 'tv' ? MediaType.tv : MediaType.movie,
              id: item.mediaId,
              title: item.title,
              posterPath: item.posterPath,
            );
            context.push(
              '/player',
              extra: PlayerArgs(
                details: details,
                season: item.season,
                episode: item.episode,
                localFilePath: fp,
              ),
            );
          },
        );
      case DownloadStatus.downloading:
        // pause() existed in the notifier but was unreachable: the only
        // download list offered cancel. Pausing keeps the partial file.
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Pause download',
              icon: const Icon(
                Icons.pause_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
              onPressed: () => n.pause(item.key),
            ),
            IconButton(
              tooltip: 'Cancel download',
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
              onPressed: () => n.remove(item.key),
            ),
          ],
        );
      case DownloadStatus.queued:
        return IconButton(
          tooltip: 'Cancel download',
          icon: const Icon(
            Icons.close_rounded,
            color: AppColors.textMuted,
            size: 20,
          ),
          onPressed: () => n.remove(item.key),
        );
      case DownloadStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Resume download',
              icon: const Icon(
                Icons.play_arrow_rounded,
                color: AppColors.accent,
                size: 22,
              ),
              onPressed: () => n.resume(item.key),
            ),
            IconButton(
              tooltip: 'Delete download',
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
              onPressed: () => n.remove(item.key),
            ),
          ],
        );
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Retry download',
              icon: const Icon(
                Icons.refresh_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              // Signed CDN links expire within minutes, so a plain retry just
              // re-hits a dead URL. Re-resolve the title first.
              onPressed: () => _retryWithFreshSource(context, ref, n),
            ),
            IconButton(
              tooltip: 'Delete download',
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
              onPressed: () => n.remove(item.key),
            ),
          ],
        );
    }
  }
}
