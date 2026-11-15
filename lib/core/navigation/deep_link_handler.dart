import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Listens for incoming app-links (universal links / deep links) and navigates
/// the GoRouter to the matching in-app route.
///
/// Supported URLs:
///   - https://www.themoviedb.org/movie/:id
///   - https://themoviedb.org/movie/:id
///   - https://www.themoviedb.org/tv/:id
///   - (future) aeroflix://movie/:id, aeroflix://tv/:id, aeroflix://person/:id
class DeepLinkHandler extends StatefulWidget {
  final Widget child;
  final GoRouter router;
  const DeepLinkHandler({super.key, required this.child, required this.router});

  @override
  State<DeepLinkHandler> createState() => _DeepLinkHandlerState();
}

class _DeepLinkHandlerState extends State<DeepLinkHandler> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _init();
  }

  Future<void> _init() async {
    // Handle the link that launched the app.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null && mounted) _handle(initial);
    } catch (_) {}
    _sub = _appLinks.uriLinkStream.listen((uri) {
      if (mounted) _handle(uri);
    }, onError: (_) {});
  }

  void _handle(Uri uri) {
    final route = _resolve(uri);
    if (route != null) widget.router.push(route);
  }

  String? _resolve(Uri uri) {
    // aeroflix://movie/123, aeroflix://tv/456, aeroflix://person/789
    if (uri.scheme == 'aeroflix') {
      final segs = uri.pathSegments;
      if (segs.length >= 2) {
        final kind = segs[0];
        final id = int.tryParse(segs[1]);
        if (id != null) {
          switch (kind) {
            case 'movie':
              return '/details/movie/$id';
            case 'tv':
              return '/details/tv/$id';
            case 'person':
              return '/person/$id?name=&profile=';
          }
        }
      }
      return null;
    }
    // themoviedb.org URLs (shared from our share sheet, TMDB web, etc.)
    final host = uri.host.replaceAll('www.', '');
    if (host != 'themoviedb.org' && host != 'tmdb.org') return null;
    final segs = uri.pathSegments;
    if (segs.length < 2) return null;
    final kind = segs[0];
    final id = int.tryParse(segs[1]);
    if (id == null) return null;
    switch (kind) {
      case 'movie':
        return '/details/movie/$id';
      case 'tv':
        return '/details/tv/$id';
      case 'person':
        return '/person/$id?name=&profile=';
    }
    return null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
