import 'dart:async';

import 'package:flutter/material.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/search_filters.dart';
import '../anime/data/models/video_quality.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../anime/data/repositories/catalog_repository.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/app_search_bar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_title.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/result_tile.dart';

/// Écran de recherche avec filtres (Saison, Épisode, Qualité, Langue, Genre,
/// Source) et résultats issus des données locales.
///
/// En mode backend ([CatalogRepository]), la recherche est déléguée au
/// serveur (titre canonique, original, alternatifs, alias) avec les états
/// d'interface : récupération en cours / trouvées / introuvables /
/// correspondance incertaine / erreur / données hors-ligne.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.repository});

  final AnimeRepository repository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  SearchFilters _filters = SearchFilters.empty;
  String _query = '';

  // ---- Recherche distante (catalogue backend) ----
  Timer? _debounce;
  int _requestSeq = 0;
  bool _remoteLoading = false;
  CatalogSearchStatus _remoteStatus = CatalogSearchStatus.found;
  List<Anime> _remoteResults = const [];
  String? _remoteMessage;

  CatalogRepository? get _catalog =>
      widget.repository is CatalogRepository ? widget.repository as CatalogRepository : null;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final SearchFilters? result = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (BuildContext context) => FilterSheet(repository: widget.repository, initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _filters = SearchFilters.empty;
      _remoteResults = const [];
      _remoteMessage = null;
      _remoteLoading = false;
    });
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value);
    final CatalogRepository? catalog = _catalog;
    if (catalog == null || value.trim().isEmpty) {
      setState(() {
        _remoteResults = const [];
        _remoteMessage = null;
        _remoteLoading = false;
      });
      return;
    }
    // Anti-rebond : on attend une courte pause de saisie avant la requête.
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runRemoteSearch(catalog, value.trim());
    });
  }

  Future<void> _runRemoteSearch(CatalogRepository catalog, String query) async {
    final int seq = ++_requestSeq;
    setState(() => _remoteLoading = true);
    final CatalogSearchResult result = await catalog.searchCatalog(query);
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _remoteLoading = false;
      _remoteStatus = result.status;
      _remoteResults = result.anime;
      _remoteMessage = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CatalogRepository? catalog = _catalog;
    final bool remoteMode = catalog != null && _query.trim().isNotEmpty;
    final bool isFiltering = _filters.isActive || _query.trim().isNotEmpty;
    final List<Anime> results = isFiltering ? widget.repository.search(_query, filters: _filters) : const [];

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: AppSearchBar(
              controller: _controller,
              hint: 'Rechercher un animé…',
              onChanged: _onQueryChanged,
              onFilterTap: _openFilters,
              activeFilterCount: _filters.activeCount,
            ),
          ),
          if (_filters.isActive)
            _ActiveFilterChips(
              filters: _filters,
              onChanged: (SearchFilters filters) => setState(() => _filters = filters),
            ),
          Expanded(
            child: remoteMode
                ? _RemoteSearchBody(
                    loading: _remoteLoading,
                    status: _remoteStatus,
                    results: _remoteResults,
                    message: _remoteMessage,
                    onRetry: () => _runRemoteSearch(catalog, _query.trim()),
                    onTap: (Anime anime) => Navigator.of(context).pushNamed(
                      AppRoutes.animeDetails,
                      arguments: AnimeIdArgs(anime.id),
                    ),
                  )
                : !isFiltering
                    ? _TrendingGrid(repository: widget.repository)
                    : results.isEmpty
                        ? EmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'Aucun résultat',
                            message: 'Aucun animé ne correspond à « ${_query.trim()} ». '
                                'Essayez d\'autres mots-clés ou retirez des filtres.',
                            actionLabel: 'Tout effacer',
                            onAction: _clearSearch,
                          )
                        : _ResultsList(results: results),
          ),
        ],
      ),
    );
  }
}

/// Corps de la recherche distante : états d'interface explicites
/// (récupération / trouvées / introuvables / incertaines / erreur /
/// hors-ligne).
class _RemoteSearchBody extends StatelessWidget {
  const _RemoteSearchBody({
    required this.loading,
    required this.status,
    required this.results,
    required this.message,
    required this.onRetry,
    required this.onTap,
  });

  final bool loading;
  final CatalogSearchStatus status;
  final List<Anime> results;
  final String? message;
  final VoidCallback onRetry;
  final ValueChanged<Anime> onTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBright),
            ),
            SizedBox(height: 12),
            Text('Récupération en cours…', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    switch (status) {
      case CatalogSearchStatus.offline:
        return _OfflineResults(results: results, onRetry: onRetry, onTap: onTap);
      case CatalogSearchStatus.error:
        return EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Actualisation impossible',
          message: 'Le backend est injoignable pour le moment. '
              'Les dernières données connues restent disponibles dans la bibliothèque.',
          actionLabel: 'Réessayer',
          onAction: onRetry,
        );
      case CatalogSearchStatus.notFound:
        return EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Aucun résultat',
          message: message ?? 'Aucun animé ne correspond à cette recherche.',
        );
      case CatalogSearchStatus.found:
      case CatalogSearchStatus.review:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.help_outline_rounded, size: 15, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(message!, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            Expanded(child: _ResultsList(results: results, onTap: onTap, showMetadataStatus: true)),
          ],
        );
      case CatalogSearchStatus.loading:
        return const SizedBox.shrink();
    }
  }
}

/// Hors-ligne : résultats issus des dernières données connues (cache local),
/// avec une indication claire.
class _OfflineResults extends StatelessWidget {
  const _OfflineResults({required this.results, required this.onRetry, required this.onTap});

  final List<Anime> results;
  final VoidCallback onRetry;
  final ValueChanged<Anime> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 2, 20, 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hors-ligne — résultats issus des données locales.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: const Text('Réessayer', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Aucun résultat local',
                  message: 'Aucune donnée connue ne correspond à cette recherche.',
                )
              : _ResultsList(results: results, onTap: onTap, showMetadataStatus: true),
        ),
      ],
    );
  }
}

/// Grille « Tendances » affichée quand aucune recherche n'est saisie.
class _TrendingGrid extends StatelessWidget {
  const _TrendingGrid({required this.repository});

  final AnimeRepository repository;

  @override
  Widget build(BuildContext context) {
    final List<Anime> anime = repository.allAnime;
    return CustomScrollView(
      key: const PageStorageKey<String>('search-trending'),
      slivers: [
        const SliverToBoxAdapter(child: SectionTitle(title: 'Tendances')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 14,
              childAspectRatio: 0.58,
            ),
            itemCount: anime.length,
            itemBuilder: (BuildContext context, int index) => AnimeCard(
              anime: anime[index],
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.animeDetails, arguments: AnimeIdArgs(anime[index].id)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Liste des résultats de recherche.
class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results, this.onTap, this.showMetadataStatus = false});

  final List<Anime> results;
  final ValueChanged<Anime>? onTap;
  final bool showMetadataStatus;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const PageStorageKey<String>('search-results'),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
      itemCount: results.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text('${results.length} résultat(s)', style: Theme.of(context).textTheme.labelSmall),
          );
        }
        final Anime anime = results[index - 1];
        return ResultTile(
          anime: anime,
          showMetadataStatus: showMetadataStatus,
          onTap: onTap != null
              ? () => onTap!(anime)
              : () => Navigator.of(context).pushNamed(AppRoutes.animeDetails, arguments: AnimeIdArgs(anime.id)),
        );
      },
    );
  }
}

/// Rangée de filtres actifs, chacun étant retirable d'un appui.
class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.filters, required this.onChanged});

  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<(String, VoidCallback)> chips = [];
    if (filters.season != null) chips.add(('Saison ${filters.season}', () => onChanged(filters.copyWith(season: null))));
    if (filters.episode != null) chips.add(('Épisode ${filters.episode}', () => onChanged(filters.copyWith(episode: null))));
    if (filters.quality != null) chips.add((filters.quality!.label, () => onChanged(filters.copyWith(quality: null))));
    if (filters.language != null) chips.add((filters.language!, () => onChanged(filters.copyWith(language: null))));
    if (filters.source != null) chips.add((filters.source!, () => onChanged(filters.copyWith(source: null))));
    for (final String genre in filters.genres) {
      chips.add((genre, () => onChanged(filters.copyWith(genres: Set<String>.from(filters.genres)..remove(genre)))));
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final (String label, VoidCallback onTap) = chips[index];
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 7, 9, 7),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryBright)),
                  const SizedBox(width: 5),
                  Icon(Icons.close_rounded, size: 14, color: AppColors.primaryBright),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
