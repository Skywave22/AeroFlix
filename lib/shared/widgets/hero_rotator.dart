import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../providers/watchlist_provider.dart';
import 'cinematic_hero_banner.dart';
import 'hero_item.dart';

/// Auto-rotating PageView hero banner, mixing movies and TV shows.
class HeroRotator extends ConsumerStatefulWidget {
  final List<HeroItem> items;
  final void Function(HeroItem) onPlay;
  final void Function(HeroItem) onDetails;
  final void Function(HeroItem, bool inWatchlist) onWatchlist;
  final bool Function(HeroItem) isInWatchlist;
  const HeroRotator({
    super.key,
    required this.items,
    required this.onPlay,
    required this.onDetails,
    required this.onWatchlist,
    required this.isInWatchlist,
  });
  @override
  ConsumerState<HeroRotator> createState() => _HeroRotatorState();
}

class _HeroRotatorState extends ConsumerState<HeroRotator> {
  late final PageController _pc;
  Timer? _t;
  bool _paused = false;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _pc = PageController(viewportFraction: 1, keepPage: true);
    _schedule();
  }

  void _schedule() {
    _t?.cancel();
    if (_paused || widget.items.length < 2) return;
    _t = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      final next = (_i + 1) % widget.items.length;
      _pc.animateToPage(next,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void didUpdateWidget(covariant HeroRotator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _i = 0;
      _schedule();
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _pc.dispose();
    super.dispose();
  }

  String _meta(HeroItem m) {
    final parts = <String>[];
    if (m.year.isNotEmpty) parts.add(m.year);
    parts.add(m.kind == 'tv' ? 'TV Series' : 'Movie');
    if (m.voteAverage > 0) {
      parts.add('★ ${m.voteAverage.toStringAsFixed(1)}');
    }
    return parts.join('  ·  ');
  }

  String _key(HeroItem m) => '${m.kind}:${m.id}';

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Container(
          height: MediaQuery.sizeOf(context).height * 0.58,
          color: AppColors.surface);
    }
    return NotificationListener<ScrollStartNotification>(
        onNotification: (_) {
          _paused = true;
          _t?.cancel();
          return false;
        },
        child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              Future.delayed(const Duration(seconds: 10), () {
                if (mounted) {
                  setState(() => _paused = false);
                  _schedule();
                }
              });
              return false;
            },
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.58,
                child: Stack(children: [
                  Positioned.fill(
                      child: PageView.builder(
                          controller: _pc,
                          itemCount: widget.items.length,
                          onPageChanged: (i) => setState(() => _i = i),
                          itemBuilder: (c, i) {
                            final m = widget.items[i];
                            final inWl = widget.isInWatchlist(m);
                            return CinematicHeroBanner(
                              backdropUrl: m.backdropUrl,
                              title: m.title,
                              metadata: _meta(m),
                              description: m.overview,
                              isInWatchlist: inWl,
                              onPlay: () => widget.onPlay(m),
                              onDetails: () => widget.onDetails(m),
                              onWatchlist: () => widget.onWatchlist(m, inWl),
                            );
                          })),
                  Positioned(
                      bottom: 18,
                      left: 0,
                      right: 0,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var k = 0; k < widget.items.length; k++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                width: k == _i ? 16 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: k == _i
                                        ? AppColors.accent
                                        : Colors.white.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(3)),
                              )
                          ])),
                ]))));
  }
}
