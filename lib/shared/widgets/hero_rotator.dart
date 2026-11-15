import 'dart:async';
import 'package:flutter/material.dart';
import '../models/movie.dart';
import 'cinematic_hero_banner.dart';
import '../../app/theme/app_colors.dart';

/// Auto-rotating hero banner that cycles through the given [movies] on a
/// [interval]. Manual horizontal swipes also advance. A dots indicator shows
/// the current index.
class HeroRotator extends StatefulWidget {
  final List<Movie> movies;
  final Duration interval;
  final void Function(Movie m)? onPlay;
  final void Function(Movie m)? onDetails;
  final bool Function(Movie m) isInWatchlist;
  final void Function(Movie m) onWatchlist;
  final String Function(Movie m) metadataOf;
  const HeroRotator({
    super.key,
    required this.movies,
    required this.metadataOf,
    required this.onPlay,
    required this.onDetails,
    required this.isInWatchlist,
    required this.onWatchlist,
    this.interval = const Duration(seconds: 6),
  });

  @override
  State<HeroRotator> createState() => _HeroRotatorState();
}

class _HeroRotatorState extends State<HeroRotator> {
  late final PageController _pc;
  Timer? _timer;
  int _idx = 0;
  bool _userInteracting = false;

  @override
  void initState() {
    super.initState();
    _pc = PageController(viewportFraction: 1);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.movies.length <= 1) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (_userInteracting || !mounted) return;
      final next = (_idx + 1) % widget.movies.length;
      _pc.animateToPage(next,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final movies = widget.movies.take(8).toList();
    return SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Stack(children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification) {
                _userInteracting = true;
              } else if (n is ScrollEndNotification) {
                _userInteracting = false;
              }
              return false;
            },
            child: PageView.builder(
                controller: _pc,
                onPageChanged: (i) => setState(() => _idx = i),
                itemCount: movies.length,
                itemBuilder: (_, i) {
                  final m = movies[i];
                  return CinematicHeroBanner(
                    key: ValueKey('hero-${m.id}'),
                    backdropUrl: m.backdropUrlW1280,
                    title: m.title,
                    metadata: widget.metadataOf(m),
                    description: m.overview,
                    onPlay: () => widget.onPlay?.call(m),
                    onDetails: () => widget.onDetails?.call(m),
                    onWatchlist: () => widget.onWatchlist(m),
                    isInWatchlist: widget.isInWatchlist(m),
                  );
                }),
          ),
          if (movies.length > 1)
            Positioned(
                left: 0,
                right: 0,
                bottom: 14,
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < movies.length; i++)
                        AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: _idx == i ? 22 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                                color: _idx == i
                                    ? AppColors.accent
                                    : Colors.white.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(4)))
                    ])),
        ]));
  }
}
