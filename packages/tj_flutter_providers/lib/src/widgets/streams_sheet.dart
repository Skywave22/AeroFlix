import 'package:flutter/material.dart';

import '../models.dart';
import '../provider_service.dart';

/// Bottom sheet that fetches streams for a TMDB title and lets the user pick one.
///
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => StreamsSheet(
///     service: service,
///     tmdbId: '27205',
///     mediaType: 'movie',
///     title: 'Inception',
///     onPlay: (stream) => myPlayer.open(stream),   // your player
///   ),
/// );
/// ```
class StreamsSheet extends StatefulWidget {
  final ProviderService service;
  final String tmdbId;
  final String mediaType; // "movie" | "tv"
  final int? season;
  final int? episode;
  final String? title;
  final void Function(StreamResult stream) onPlay;
  final List<String>? onlyProviderIds;

  const StreamsSheet({
    super.key,
    required this.service,
    required this.tmdbId,
    required this.mediaType,
    this.season,
    this.episode,
    this.title,
    required this.onPlay,
    this.onlyProviderIds,
  });

  @override
  State<StreamsSheet> createState() => _StreamsSheetState();
}

class _StreamsSheetState extends State<StreamsSheet> {
  List<StreamResult>? _streams;
  String? _error;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _streams = null;
      _error = null;
    });
    try {
      final streams = await widget.service.getStreams(
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        season: widget.season,
        episode: widget.episode,
        onlyProviderIds: widget.onlyProviderIds,
      );
      if (mounted) setState(() => _streams = streams);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<StreamResult> get _filtered {
    final all = _streams ?? const <StreamResult>[];
    if (_filter == 'All') return all;
    if (_filter == 'Hindi') {
      return all
          .where(
            (s) =>
                '${s.language ?? ''} ${s.name}'.toLowerCase().contains('hindi'),
          )
          .toList();
    }
    if (_filter == '4K') {
      final q = (s) => s.quality.toLowerCase();
      return all
          .where((s) => q(s).contains('2160') || q(s).contains('4k'))
          .toList();
    }
    return all
        .where((s) => s.quality.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title ?? 'Streams',
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(_subtitle(), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh streams',
                    onPressed: _streams == null ? null : _load,
                  ),
                ],
              ),
            ),
            if (_streams != null && _streams!.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final f in const [
                      'All',
                      'Hindi',
                      '4K',
                      '1080p',
                      '720p',
                      '480p',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(child: _body(controller)),
          ],
        );
      },
    );
  }

  String _subtitle() {
    if (_error != null) return 'Failed to load';
    if (_streams == null) return 'Searching providers…';
    if (_streams!.isEmpty) return 'No working links found';
    final providers = _streams!
        .map((s) => s.provider)
        .where((p) => p.isNotEmpty)
        .toSet();
    return '${_streams!.length} links from ${providers.length} provider(s)';
  }

  Widget _body(ScrollController controller) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 40),
              const SizedBox(height: 12),
              Text(
                'Could not load streams\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_streams == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking provider links…\nthis can take up to 60s'),
          ],
        ),
      );
    }
    if (_streams!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off, size: 40),
              const SizedBox(height: 12),
              const Text(
                'No working links right now.\n'
                'Titles often are not on every site — try another provider or check for provider updates.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return const Center(child: Text('No links match this filter'));
    }

    return ListView.builder(
      controller: controller,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final s = items[i];
        return ListTile(
          leading: _QualityBadge(quality: s.quality),
          title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (s.language != null && s.language!.isNotEmpty) s.language!,
              if (s.size != null && s.size!.isNotEmpty) s.size!,
              if (s.subtitles.isNotEmpty) '${s.subtitles.length} subtitle(s)',
              s.isHls
                  ? 'HLS'
                  : s.isMkv
                  ? 'MKV'
                  : s.isMp4
                  ? 'MP4'
                  : 'stream',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.play_circle_fill, size: 32),
          onTap: () {
            Navigator.of(context).maybePop();
            widget.onPlay(s);
          },
        );
      },
    );
  }
}

class _QualityBadge extends StatelessWidget {
  final String quality;
  const _QualityBadge({required this.quality});

  @override
  Widget build(BuildContext context) {
    final q = quality.toUpperCase().replaceAll('P', 'p');
    final isHigh = q.contains('4K') || q.contains('2160') || q.contains('1080');
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isHigh
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        q.length > 6 ? q.substring(0, 6) : q,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isHigh ? Colors.green.shade300 : Colors.orange.shade300,
        ),
      ),
    );
  }
}
