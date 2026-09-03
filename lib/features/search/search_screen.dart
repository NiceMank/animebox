import 'package:flutter/material.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/search_filters.dart';
import '../anime/data/models/video_quality.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/app_search_bar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_title.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/result_tile.dart';

/// Écran de recherche avec filtres (Saison, Épisode, Qualité, Langue, Genre,
/// Source) — résultats issus des données locales de l'appareil (titre
/// canonique, original, alternatifs, alias indexés localement).
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

  @override
  void dispose() {
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
    _controller.clear();
    setState(() {
      _query = '';
      _filters = SearchFilters.empty;
    });
  }

  void _onQueryChanged(String value) => setState(() => _query = value);

  @override
  Widget build(BuildContext context) {
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
            child: !isFiltering
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
  const _ResultsList({required this.results});

  final List<Anime> results;

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
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.animeDetails, arguments: AnimeIdArgs(anime.id)),
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
