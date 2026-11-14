import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/tmdb_service.dart';
import '../../shared/models/person.dart';
import '../../shared/widgets/poster_card.dart';

class PersonArgs {
  final int id;
  final String name;
  final String? profilePath;
  const PersonArgs({required this.id, required this.name, this.profilePath});
}

class PersonScreen extends ConsumerStatefulWidget {
  final PersonArgs args;
  const PersonScreen({super.key, required this.args});

  @override
  ConsumerState<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends ConsumerState<PersonScreen> {
  late Future<_PersonData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PersonData> _load() async {
    final svc = ref.read(tmdbServiceProvider);
    final combined = await svc.getPersonCredits(widget.args.id);
    final info = await svc.getPersonInfo(widget.args.id);
    return _PersonData(info: info, credits: combined);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.background,
        body: FutureBuilder<_PersonData>(
            future: _future,
            builder: (c, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return CustomScrollView(slivers: [
                  SliverAppBar(
                      pinned: true,
                      leading: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 20),
                          onPressed: () => context.pop())),
                  const SliverFillRemaining(
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 2))),
                ]);
              }
              if (snap.hasError || !snap.hasData) {
                return CustomScrollView(slivers: [
                  SliverAppBar(
                      pinned: true,
                      leading: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 20),
                          onPressed: () => context.pop())),
                  SliverFillRemaining(
                      child: Center(
                          child: FilledButton.tonal(
                              onPressed: () =>
                                  setState(() => _future = _load()),
                              child: const Text('Retry')))),
                ]);
              }
              final d = snap.data!;
              return _Content(data: d, initialName: widget.args.name);
            }));
  }
}

class _PersonData {
  final PersonInfo info;
  final PersonCredits credits;
  _PersonData({required this.info, required this.credits});
}

class _Content extends StatelessWidget {
  final _PersonData data;
  final String initialName;
  const _Content({required this.data, required this.initialName});

  @override
  Widget build(BuildContext context) {
    final info = data.info;
    final credits = data.credits;
    final name = info.name.isNotEmpty ? info.name : initialName;
    final meta = <String>[];
    if (info.birthday != null) {
      try {
        final b = DateTime.parse(info.birthday!);
        meta.add('Born ${DateFormat.yMMMd().format(b)}');
        if (info.deathday != null) {
          final dth = DateTime.parse(info.deathday!);
          meta.add('Died ${DateFormat.yMMMd().format(dth)}');
        } else {
          final age = DateTime.now().difference(b).inDays ~/ 365;
          meta.add('$age yrs');
        }
      } catch (_) {}
    }
    if (info.placeOfBirth != null && info.placeOfBirth!.isNotEmpty) {
      meta.add(info.placeOfBirth!);
    }

    return CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
      SliverAppBar(
          pinned: true,
          expandedHeight: 300,
          backgroundColor: AppColors.background,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
              splashRadius: 20),
          flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
            if (info.profilePath != null)
              CachedNetworkImage(
                  imageUrl:
                      ApiConstants.profileUrl(info.profilePath, size: 'h632'),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter)
            else
              Container(color: AppColors.surface),
            const DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x66090A0D), AppColors.background],
                        stops: [0.0, 1.0]))),
          ]))),
      SliverToBoxAdapter(
          child: Padding(
              padding: AppSpacing.screenHorizontal,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppTypography.display.copyWith(fontSize: 26)),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(meta.join('  ·  '),
                          style: AppTypography.metadata
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                    if (info.biography.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text('Biography', style: AppTypography.sectionHeading),
                      const SizedBox(height: AppSpacing.sm),
                      Text(info.biography,
                          style: AppTypography.body.copyWith(height: 1.6)),
                    ],
                  ]))),
      if (credits.movies.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
            child: Padding(
                padding: AppSpacing.screenHorizontal,
                child: Text('Movies', style: AppTypography.sectionHeading))),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
        SliverToBoxAdapter(
            child: SizedBox(
                height: AppSpacing.posterHeight + 56,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: AppSpacing.screenHorizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: credits.movies.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (_, i) {
                      final m = credits.movies[i];
                      return PosterCard(
                          imageUrl: m.posterUrlW342,
                          title: m.title,
                          metadata: m.year,
                          onTap: () => context.push(
                              '/details/movie/${m.id}?poster=${Uri.encodeComponent(m.posterUrlW342)}'));
                    }))),
      ],
      if (credits.tv.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
            child: Padding(
                padding: AppSpacing.screenHorizontal,
                child: Text('TV Shows', style: AppTypography.sectionHeading))),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
        SliverToBoxAdapter(
            child: SizedBox(
                height: AppSpacing.posterHeight + 56,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: AppSpacing.screenHorizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: credits.tv.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (_, i) {
                      final s = credits.tv[i];
                      return PosterCard(
                          imageUrl: s.posterUrlW342,
                          title: s.name,
                          metadata: s.year,
                          onTap: () => context.push(
                              '/details/tv/${s.id}?poster=${Uri.encodeComponent(s.posterUrlW342)}'));
                    }))),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 100)),
    ]);
  }
}
