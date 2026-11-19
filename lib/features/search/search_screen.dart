import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../shared/widgets/section_placeholder.dart';
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

  // Paging: the API returns 20 results per page and `totalPages`, which nothing
  // used to read, so search silently stopped after page 1.
  //
  // `_page` is the last page appended, `_window` covers both the search term
  // and the paging state, so a new query can never append onto the previous
  // term's results.
  int _page = 1;
  int _totalPages = 1;
  bool _loadingMore = false;
  _SearchWindow? _window;
  final List<Movie> _appended = [];
  final List<TvShow> _appendedTv = [];
  final List<PersonSearchResult> _appendedPeople = [];

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
    final list = [
      q.trim(),
      ..._recent.where((r) => r != q.trim()),
    ].take(10).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(AppConstants.prefRecentSearches, list);
    setState(() => _recent = list);
  }

  /// [remember] is only true for an explicit search (keyboard submit or a
  /// tapped suggestion). The debounced search used to record every prefix the
  /// user paused on ("ava", "avat", "avatar").
  void _doSearch(String q, {bool remember = false}) {
    if (remember) _saveRecent(q);
    _page = 1;
    _totalPages = 1;
    _appended.clear();
    _appendedTv.clear();
    _appendedPeople.clear();
    _window = null;
    setState(() {
      _future = ref.read(tmdbServiceProvider).searchMulti(q, page: 1);
      _loading = false;
    });
  }

  /// Append the next page of results to the current query.
  Future<void> _loadMore() async {
    final w = _window;
    if (w == null || w.totalPages <= 1 || _loadingMore) return;
    if (_page >= w.totalPages) return;
    setState(() => _loadingMore = true);
    try {
      final next = await ref
          .read(tmdbServiceProvider)
          .searchMulti(w.query, page: _page + 1);
      // The user may have typed a different query while this page was loading.
      if (!mounted || _window != w) return;
      setState(() {
        _page += 1;
        _totalPages = (next['totalPages'] as int?) ?? _totalPages;
        _appended.addAll(_as<Movie>(next['movies']));
        _appendedTv.addAll(_as<TvShow>(next['tv']));
        _appendedPeople.addAll(_as<PersonSearchResult>(next['people']));
      });
    } catch (_) {
      // A failed extra page is not fatal: the rows already on screen stay.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _openMovie(Movie m) => context.push(
    '/details/movie/${m.id}?poster=${Uri.encodeComponent(m.posterUrlW342)}',
  );
  void _openTv(TvShow s) => context.push(
    '/details/tv/${s.id}?poster=${Uri.encodeComponent(s.posterUrlW342)}',
  );
  void _openPerson(PersonSearchResult p) => context.push(
    '/person/${p.id}?name=${Uri.encodeComponent(p.name)}&profile=${Uri.encodeComponent(p.profilePath ?? '')}',
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.horizontalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.md),
            Text('Search', style: AppTypography.screenHeading),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _c,
              style: AppTypography.bodyPrimary,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                if (v.trim().length >= 2) {
                  _doSearch(v.trim(), remember: true);
                }
              },
              decoration: InputDecoration(
                hintText: 'Movies, shows, actors…',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textMuted,
                ),
                suffixIcon: _c.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(
                          Icons.clear,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        onPressed: () {
                          _c.clear();
                          setState(() {
                            _future = null;
                            _window = null;
                            _page = 1;
                            _totalPages = 1;
                            _appended.clear();
                            _appendedTv.clear();
                            _appendedPeople.clear();
                          });
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    ),
  );

  Widget _buildResults() {
    final query = _c.text.trim();
    if (query.isEmpty || query.length < 2) {
      return _buildIdle();
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      );
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.accent,
              strokeWidth: 2,
            ),
          );
        }
        if (snap.hasError) {
          return Center(
            child: SectionErrorState(
              message: 'Search failed — check your connection',
              onRetry: () => _doSearch(query),
            ),
          );
        }
        final data = snap.data ?? {};
        // Remember which term this payload belongs to, so _loadMore() appends
        // the right page and the footer reflects the real total.
        // `totalPages` is identical on every page, so recording it here also
        // covers a retry of page 1 after a failure.
        final total = (data['totalPages'] as int?) ?? 1;
        if (_window?.query != query) {
          _window = _SearchWindow(query: query, totalPages: total);
        }
        _totalPages = total;
        final movies = [
          ...(data['movies'] as List?)?.cast<Movie>() ?? const <Movie>[],
          ..._appended,
        ];
        final tv = [
          ...(data['tv'] as List?)?.cast<TvShow>() ?? const <TvShow>[],
          ..._appendedTv,
        ];
        final people = [
          ...(data['people'] as List?)?.cast<PersonSearchResult>() ??
              const <PersonSearchResult>[],
          ..._appendedPeople,
        ];
        if (movies.isEmpty && tv.isEmpty && people.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    color: AppColors.textMuted,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No results for "$query"',
                    style: AppTypography.bodyPrimary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try different keywords.',
                    style: AppTypography.metadata.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            if (movies.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text('Movies', style: AppTypography.sectionHeading),
              ),
              SizedBox(
                height: AppSpacing.posterRowFor(context),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: movies.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (_, i) => PosterCard(
                    imageUrl: movies[i].posterUrlW342,
                    title: movies[i].title,
                    metadata: movies[i].year,
                    onTap: () => _openMovie(movies[i]),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (tv.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text('TV Shows', style: AppTypography.sectionHeading),
              ),
              SizedBox(
                height: AppSpacing.posterRowFor(context),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tv.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (_, i) => PosterCard(
                    imageUrl: tv[i].posterUrlW342,
                    title: tv[i].name,
                    metadata: tv[i].year,
                    onTap: () => _openTv(tv[i]),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (people.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text('People', style: AppTypography.sectionHeading),
              ),
              for (final p in people.take(10))
                _PersonResult(p: p, onTap: () => _openPerson(p)),
            ],
            // Page 1 used to be the whole result set with no hint that more
            // existed. Offer the next page explicitly — but only when there is
            // actually a next page to ask the API for (more than one row can
            // show a total > 1 and still have every category empty).
            if (_page < _totalPages && (movies.isNotEmpty || tv.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Center(
                  child: _loadingMore
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : OutlinedButton(
                          onPressed: _loadMore,
                          child: Text(
                            'Load more (page ${_page + 1} of '
                            '$_totalPages)',
                          ),
                        ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  Widget _buildIdle() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_recent.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent searches',
                style: AppTypography.sectionHeading.copyWith(fontSize: 16),
              ),
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(AppConstants.prefRecentSearches);
                  setState(() => _recent = const []);
                },
                child: Text(
                  'Clear',
                  style: AppTypography.metadata.copyWith(
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final t in _recent)
                ActionChip(
                  label: Text(t),
                  backgroundColor: AppColors.surface,
                  labelStyle: AppTypography.metadata.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadii.smRadius,
                  ),
                  onPressed: () {
                    _c.text = t;
                    _c.selection = TextSelection.fromPosition(
                      TextPosition(offset: t.length),
                    );
                    _doSearch(t);
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        Text(
          'Browse by genre',
          style: AppTypography.sectionHeading.copyWith(fontSize: 16),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Keyword search is above; Explore has real TMDB genre filters.',
          style: AppTypography.metadata.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            ActionChip(
              label: const Text('Open Explore'),
              avatar: const Icon(
                Icons.explore_outlined,
                size: 16,
                color: AppColors.accent,
              ),
              backgroundColor: AppColors.surface,
              labelStyle: AppTypography.metadata.copyWith(
                color: AppColors.textSecondary,
              ),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: AppRadii.smRadius),
              onPressed: () => context.go('/explore'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// The first-page result set a search's paging state belongs to.
class _SearchWindow {
  const _SearchWindow({required this.query, required this.totalPages});
  final String query;
  final int totalPages;
}

/// TMDB payload lists arrive as `List<dynamic>`; an unexpected shape should
/// yield an empty list rather than throw and blank the whole screen.
List<T> _as<T>(Object? value) =>
    value is List ? value.whereType<T>().toList() : const [];

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
          child: Row(
            children: [
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
                            child: const Icon(
                              Icons.person,
                              color: AppColors.textMuted,
                              size: 24,
                            ),
                          ),
                        )
                      : Container(
                          color: AppColors.surface,
                          child: const Icon(
                            Icons.person,
                            color: AppColors.textMuted,
                            size: 24,
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
                      p.name,
                      style: AppTypography.cardTitle.copyWith(fontSize: 14),
                    ),
                    if (p.knownForLabel().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        p.knownForLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.metadata.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
