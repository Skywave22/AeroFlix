import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Real, in-app "About / Privacy" content. No external page, no dead link.
class AboutSheet extends StatelessWidget {
  const AboutSheet(
      {super.key, required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  static Future<void> show(BuildContext context,
      {required String version, required String build}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (_) => AboutSheet(version: version, buildNumber: build),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(AppSpacing.horizontalPadding),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Image.asset('assets/images/logo_mark.png', width: 48, height: 48),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AeroFlix',
                      style:
                          AppTypography.sectionHeading.copyWith(fontSize: 24)),
                  Text('Version $version ($buildNumber)',
                      style: AppTypography.caption),
                ],
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _Heading('What this app does'),
          _Body('AeroFlix is a catalogue browser for movies, series and anime. '
              'Posters, ratings, cast and artwork come from TMDB. Playback links '
              'are resolved at request time by open-source provider plugins '
              '(TJ-Plugins) that you can see and update in Settings → Providers.'),
          _Heading('Data we store'),
          const _Bullet(
              'Watchlist, watch progress and settings — on this device only.'),
          const _Bullet(
              'Downloaded files — in app storage until you delete them.'),
          const _Bullet(
              'Provider bundles — cached from GitHub so they can auto-update.'),
          const _Body(
              'There is no account, no analytics SDK and no server of ours in the '
              'middle: the app talks to TMDB and to the providers directly.'),
          _Heading('Attribution'),
          const _Body(
              'This product uses the TMDB API but is not endorsed or certified by '
              'TMDB. Provider plugins are maintained by the TJ-Plugins project '
              '(Skywave22/Plugins-TJ) and are licensed separately.'),
          _Heading('Content'),
          const _Body(
              'AeroFlix does not host, upload or store any video. All links point to '
              'third-party services. Availability and legality of that content varies '
              'by region — you are responsible for what you choose to stream.'),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Close'),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
        child: Text(text, style: AppTypography.cardTitle),
      );
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text, style: AppTypography.body.copyWith(height: 1.55)),
      );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 8),
            child: Icon(Icons.circle, size: 5, color: AppColors.accent),
          ),
          Expanded(
              child:
                  Text(text, style: AppTypography.body.copyWith(height: 1.5))),
        ]),
      );
}
