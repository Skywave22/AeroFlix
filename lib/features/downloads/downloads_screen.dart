import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../core/constants/api_constants.dart';
import '../../shared/models/media_details.dart';
import '../../shared/providers/download_provider.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(downloadProvider);
    return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          title: Text('Downloads', style: AppTypography.cardTitle),
          actions: [
            if (items.isNotEmpty)
              TextButton(
                  onPressed: () => _confirmClearAll(context, ref),
                  child: Text('Edit',
                      style: AppTypography.metadata
                          .copyWith(color: AppColors.accent)))
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
                itemBuilder: (_, i) => _DownloadRow(item: items[i])));
  }

  Widget _emptyState() => Center(
      child: Padding(
          padding: const EdgeInsets.all(AppSpacing.horizontalPadding),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                style: AppTypography.cardTitle.copyWith(fontSize: 18)),
            const SizedBox(height: AppSpacing.xs),
            Text(
                'Tap the download icon on any movie or episode to save it for offline viewing.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.textMuted)),
          ])));

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Swipe items to delete'),
          duration: Duration(seconds: 2)));
  }
}

class _DownloadRow extends ConsumerWidget {
  final DownloadItem item;
  const _DownloadRow({required this.item});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poster =
        item.posterPath != null ? ApiConstants.posterUrl(item.posterPath) : '';
    final isDone = item.status == DownloadStatus.completed;
    final isActive = item.status == DownloadStatus.downloading;
    return Dismissible(
        key: ValueKey(item.key),
        direction: DismissDirection.endToStart,
        background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
                color: AppColors.error, borderRadius: AppRadii.mdRadius),
            child: const Icon(Icons.delete_outline, color: Colors.white)),
        onDismissed: (_) =>
            ref.read(downloadProvider.notifier).remove(item.key),
        child: Container(
            decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: AppRadii.mdRadius),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(children: [
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
                                  child: const Icon(Icons.movie,
                                      color: AppColors.textMuted, size: 22)))
                          : Container(
                              color: AppColors.surfaceElevated,
                              child: const Icon(Icons.movie,
                                  color: AppColors.textMuted, size: 22)))),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyPrimary
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.metadata.copyWith(
                            color: isDone
                                ? AppColors.success
                                : (isActive
                                    ? AppColors.accent
                                    : AppColors.textMuted),
                            fontSize: 11)),
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
                          valueColor: AlwaysStoppedAnimation<Color>(isDone
                              ? AppColors.success
                              : (item.status == DownloadStatus.failed
                                  ? AppColors.error
                                  : AppColors.accent)),
                        )),
                  ])),
              const SizedBox(width: AppSpacing.sm),
              _trailing(context, ref),
            ])));
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
        return 'Failed${item.error != null ? ' · ${item.error}' : ''}';
    }
  }

  Widget _trailing(BuildContext context, WidgetRef ref) {
    final n = ref.read(downloadProvider.notifier);
    switch (item.status) {
      case DownloadStatus.completed:
        return IconButton(
            icon: const Icon(Icons.play_arrow_rounded,
                color: AppColors.accent, size: 26),
            onPressed: () {
              final fp = item.filePath;
              if (fp == null) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                      content: Text('This download is missing its file'),
                      duration: Duration(seconds: 2)));
                return;
              }
              final details = MediaDetails(
                type: item.kind == 'tv' ? MediaType.tv : MediaType.movie,
                id: item.mediaId,
                title: item.title,
                posterPath: item.posterPath,
              );
              context.push('/player',
                  extra: PlayerArgs(
                      details: details,
                      season: item.season,
                      episode: item.episode,
                      localFilePath: fp));
            });
      case DownloadStatus.downloading:
        return IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textMuted, size: 20),
            onPressed: () => n.remove(item.key));
      case DownloadStatus.queued:
        return IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textMuted, size: 20),
            onPressed: () => n.remove(item.key));
      case DownloadStatus.paused:
        return IconButton(
            icon: const Icon(Icons.play_arrow_rounded,
                color: AppColors.accent, size: 22),
            onPressed: () => n.resume(item.key));
      case DownloadStatus.failed:
        return IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.warning, size: 20),
            onPressed: () => n.retry(item.key));
    }
  }
}
