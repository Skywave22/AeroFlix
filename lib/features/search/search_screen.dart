import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/tmdb_service.dart';
import '../../shared/models/movie.dart';
import '../../shared/models/person_search_result.dart';
import '../../shared/models/tv_show.dart';
import '../../shared/widgets/poster_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _c = TextEditingController();
  Timer? _debounce;
  Future<Map<String, dynamic>>? _future;
  List<String> _recent = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      _debounce?.cancel();
      final q = _c.text.trim();
      if (q.length < 2) {
        setState(() {
          _future = null;
          _loading = false;
        });
        return;
      }
      setState(() => _loading = true);
      _debounce = Timer(const Duration(milliseconds: 350), () {
        _doSearch(q);
      });
    });
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recent =
          prefs.getStringList(AppConstants.prefRecentSearches) ?? const [];
    });
  }

  Future<void> _saveRecent(String q) async {
    if (q.trim().isEmpty) return;
    final list =
        [q.trim(), ..._recent.where((r) => r != q.trim())].take(10).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(AppConstants.prefRecentSearches, list);
    setState(() => _recent = list);
  }

  void _doSearch(String q) {
    _saveRecent(q);
    setState(() {
      _future = ref.read(tmdbServiceProvider).searchMulti(q);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _openMovie(Movie m) => context.push(
      '/details/movie/${m.id}?poster=${Uri.encodeComponent(m.posterUrlW342)}');
  void _openTv(TvShow s) => context.push(
      '/details/tv/${s.id}?poster=${Uri.encodeComponent(s.posterUrlW342)}');
  void _openPerson(PersonSearchResult p) => context.push(
      '/person/${p.id}?name=${Uri.encodeComponent(p.name)}&profile=${Uri.encodeComponent(p.profilePath ?? '')}');

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.horizontalPadding),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    Text('Search', style: AppTypography.screenHeading),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                        controller: _c,
                        autofocus: true,
                        style: AppTypography.bodyPrimary,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (v) {
                          if (v.trim().length >= 2) _doSearch(v.trim());
                        },
                        decoration: InputDecoration(
                            hintText: 'Movies, shows, actors…',
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: AppColors.textMuted),
                            suffixIcon: _c.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear,
                                        color: AppColors.textMuted, size: 20),
                                    onPressed: () {
                                      _c.clear();
                                      setState(() {
                                        _future = null;
                                      });
                                    })
                                : null)),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(child: _buildResults()),
                  ]))));

  Widget _buildResults() {
    final query = _c.text.trim();
    if (query.isEmpty || query.length < 2) {
      return _buildIdle();
    }
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2));
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2));
        }
        if (snap.hasError) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.textMuted, size: 40),
            const SizedBox(height: 12),
            Text('Search failed', style: AppTypography.bodyPrimary),
          ]));
        }
        final data = snap.data ?? {};
        final movies =
            (data['movies'] as List?)?.cast<Movie>() ?? const <Movie>[];
        final tv = (data['tv'] as List?)?.cast<TvShow>() ?? const <TvShow>[];
        final people = (data['people'] as List?)?.cast<PersonSearchResult>() ??
            const <PersonSearchResult>[];
        if (movies.isEmpty && tv.isEmpty && people.isEmpty) {
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.search_off_rounded,
                        color: AppColors.textMuted, size: 48),
                    const SizedBox(height: 12),
                    Text('No results for "$query"',
                        style: AppTypography.bodyPrimary),
                    const SizedBox(height: 4),
                    Text('Try different keywords.',
                        style: AppTypography.metadata
                            .copyWith(color: AppColors.textMuted)),
                  ])));
        }
        return ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            if (movies.isNotEmpty) ...[
              Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text('Movies', style: AppTypography.sectionHeading)),
              SizedBox(
                  height: AppSpacing.posterHeight + 56,
                  child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: movies.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (_, i) => PosterCard(
                          imageUrl: movies[i].posterUrlW342,
                          title: movies[i].title,
                          metadata: movies[i].year,
                          onTap: () => _openMovie(movies[i])))),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (tv.isNotEmpty) ...[
              Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text('TV Shows', style: AppTypography.sectionHeading)),
              SizedBox(
                  height: AppSpacing.posterHeight + 56,
                  child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: tv.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (_, i) => PosterCard(
                          imageUrl: tv[i].posterUrlW342,
                          title: tv[i].name,
                          metadata: tv[i].year,
                          onTap: () => _openTv(tv[i])))),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (people.isNotEmpty) ...[
              Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text('People', style: AppTypography.sectionHeading)),
              for (final p in people.take(10))
                _PersonResult(p: p, onTap: () => _openPerson(p)),
              const SizedBox(height: 40),
            ],
          ],
        );
      },
    );
  }

  Widget _buildIdle() => SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_recent.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent searches',
                  style: AppTypography.sectionHeading.copyWith(fontSize: 16)),
              TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove(AppConstants.prefRecentSearches);
                    setState(() => _recent = const []);
                  },
                  child: Text('Clear',
                      style: AppTypography.metadata
                          .copyWith(color: AppColors.accent))),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
            for (final t in _recent)
              ActionChip(
                  label: Text(t),
                  backgroundColor: AppColors.surface,
                  labelStyle: AppTypography.metadata
                      .copyWith(color: AppColors.textSecondary),
                  side: BorderSide.none,
                  shape:
                      RoundedRectangleBorder(borderRadius: AppRadii.smRadius),
                  onPressed: () {
                    _c.text = t;
                    _c.selection = TextSelection.fromPosition(
                        TextPosition(offset: t.length));
                    _doSearch(t);
                  }),
          ]),
          const SizedBox(height: AppSpacing.xl),
        ],
        Text('Popular genres',
            style: AppTypography.sectionHeading.copyWith(fontSize: 16)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
          for (final t in const [
            'Action',
            'Comedy',
            'Drama',
            'Horror',
            'Sci-Fi',
            'Romance',
            'Thriller',
            'Anime',
            'Bollywood'
          ])
            ActionChip(
                label: Text(t),
                backgroundColor: AppColors.surface,
                labelStyle: AppTypography.metadata
                    .copyWith(color: AppColors.textSecondary),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: AppRadii.smRadius),
                onPressed: () {
                  _c.text = t;
                  _c.selection = TextSelection.fromPosition(
                      TextPosition(offset: t.length));
                  _doSearch(t);
                }),
        ]),
      ]));
}

class _PersonResult extends StatelessWidget {
  final PersonSearchResult p;
  final VoidCallback onTap;
  const _PersonResult({required this.p, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(children: [
                  ClipOval(
                    child: SizedBox(
                        width: 52,
                        height: 52,
                        child: p.profileUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: p.profileUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) =>
                                    Container(color: AppColors.surface),
                                errorWidget: (_, __, ___) => Container(
                                    color: AppColors.surface,
                                    child: const Icon(Icons.person,
                                        color: AppColors.textMuted, size: 24)))
                            : Container(
                                color: AppColors.surface,
                                child: const Icon(Icons.person,
                                    color: AppColors.textMuted, size: 24))),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(p.name,
                            style:
                                AppTypography.cardTitle.copyWith(fontSize: 14)),
                        if (p.knownForLabel().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(p.knownForLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.metadata.copyWith(
                                  color: AppColors.textMuted, fontSize: 12)),
                        ]
                      ])),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 20),
                ]))));
  }
}
