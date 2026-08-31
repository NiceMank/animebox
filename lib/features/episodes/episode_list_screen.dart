import 'package:flutter/material.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/episode.dart';
import '../anime/data/models/season.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/episode_card.dart';
import '../../shared/widgets/poster_image.dart';
import '../../shared/widgets/season_selector.dart';
import '../../shared/widgets/status_pill.dart';

/// Tri des épisodes.
enum EpisodeSort {
  newest('Plus récent', Icons.south_rounded),
  oldest('Plus ancien', Icons.north_rounded),
  ascending('Numéro croissant', Icons.arrow_downward_rounded),
  descending('Numéro décroissant', Icons.arrow_upward_rounded);

  const EpisodeSort(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Écran 4 — Liste des épisodes d'un animé : présentation, sélection de
/// saison (avec spéciaux), tri et navigation vers le choix de qualité.
class EpisodeListScreen extends StatefulWidget {
  const EpisodeListScreen({
    super.key,
    required this.repository,
    required this.animeId,
    this.initialSeasonId,
  });

  final AnimeRepository repository;
  final String animeId;
  final String? initialSeasonId;

  @override
  State<EpisodeListScreen> createState() => _EpisodeListScreenState();
}

class _EpisodeListScreenState extends State<EpisodeListScreen> {
  String? _selectedSeasonId;
  bool _specialsSelected = false;
  EpisodeSort _sort = EpisodeSort.newest;

  @override
  void initState() {
    super.initState();
    final Anime? anime = widget.repository.byId(widget.animeId);
    if (anime != null) {
      // Saison présélectionnée, sinon la plus récente avec des épisodes.
      final String? wanted = widget.initialSeasonId;
      if (wanted != null && anime.seasons.any((Season s) => s.id == wanted)) {
        _selectedSeasonId = wanted;
      } else {
        for (final Season season in anime.seasons.reversed) {
          if (season.episodes.isNotEmpty) {
            _selectedSeasonId = season.id;
            break;
          }
        }
      }
    }
  }

  void _openEpisode(Episode episode) {
    Navigator.of(context).pushNamed(
      AppRoutes.episodeQuality,
      arguments: EpisodeRouteArgs(animeId: widget.animeId, episodeId: episode.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Anime? anime = widget.repository.byId(widget.animeId);
    if (anime == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Animé introuvable', style: TextStyle(color: AppColors.textMuted))),
      );
    }
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (BuildContext context, Widget? child) {
        final Season? season = _selectedSeasonId == null
            ? null
            : anime.seasons.where((Season s) => s.id == _selectedSeasonId).firstOrNull;
        final List<Episode> episodes = _specialsSelected || season == null
            ? anime.seasons.expand((Season s) => s.specials).toList()
            : season.episodes;
        final List<Episode> sorted = _sorted(episodes);
        final bool isFavorite = widget.repository.libraryEntryFor(anime.id)?.isFavorite ?? false;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              anime.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                onPressed: () => widget.repository.toggleFavorite(anime.id),
                icon: Icon(
                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFavorite ? AppColors.danger : AppColors.textPrimary,
                  size: 22,
                ),
              ),
            ],
          ),
          body: CustomScrollView(
            key: const PageStorageKey<String>('episode-list-scroll'),
            slivers: [
              SliverToBoxAdapter(child: _Banner(anime: anime)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: SeasonSelector(
                    seasons: anime.seasons,
                    selectedId: _selectedSeasonId,
                    onSelected: (String? id) => setState(() {
                      _selectedSeasonId = id;
                      _specialsSelected = id == null;
                    }),
                    showSpecials: anime.hasSpecials,
                    specialsCount: anime.seasons.fold(0, (int sum, Season s) => sum + s.specials.length),
                    specialsSelected: _specialsSelected,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Row(
                    children: [
                      Text(
                        '${sorted.length} épisode${sorted.length > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      _SortButton(sort: _sort, onChanged: (EpisodeSort sort) => setState(() => _sort = sort)),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
                sliver: SliverList.separated(
                  itemCount: sorted.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Episode episode = sorted[index];
                    return EpisodeCard(
                      episode: episode,
                      progress: widget.repository.episodeProgress(anime.id, episode.id),
                      subtitle: _specialsSelected ? 'Spécial' : null,
                      onTap: () => _openEpisode(episode),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Episode> _sorted(List<Episode> episodes) {
    final List<Episode> copy = List.of(episodes);
    switch (_sort) {
      case EpisodeSort.newest:
        copy.sort((Episode a, Episode b) => b.date.compareTo(a.date));
      case EpisodeSort.oldest:
        copy.sort((Episode a, Episode b) => a.date.compareTo(b.date));
      case EpisodeSort.ascending:
        copy.sort((Episode a, Episode b) => a.number.compareTo(b.number));
      case EpisodeSort.descending:
        copy.sort((Episode a, Episode b) => b.number.compareTo(a.number));
    }
    return copy;
  }
}

/// Zone de présentation de l'animé (banner + métadonnées).
class _Banner extends StatelessWidget {
  const _Banner({required this.anime});

  final Anime anime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PosterImage(asset: anime.backdropAsset, borderRadius: 0, fallbackLabel: anime.title),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.25, 0.7, 1.0],
                    colors: [Colors.transparent, Color(0x590A0817), Color(0xF20A0817)],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            shadows: const [Shadow(color: Colors.black54, blurRadius: 10)],
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final String genre in anime.genres.take(2))
                          _MetaChip(label: genre),
                        _MetaChip(label: '★ ${anime.rating.toStringAsFixed(1)}', accent: true),
                        _MetaChip(label: '${anime.year}'),
                        _MetaChip(label: '${anime.episodeDurationMin} min/ép'),
                        StatusPill(anime.status.label, color: AppColors.success),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? AppColors.primary.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent ? AppColors.primary.withValues(alpha: 0.5) : Colors.transparent),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: accent ? AppColors.primaryBright : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onChanged});

  final EpisodeSort sort;
  final ValueChanged<EpisodeSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<EpisodeSort>(
      tooltip: 'Trier les épisodes',
      onSelected: onChanged,
      color: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (BuildContext context) => [
        for (final EpisodeSort option in EpisodeSort.values)
          PopupMenuItem<EpisodeSort>(
            value: option,
            child: Row(
              children: [
                Icon(option.icon, size: 17, color: option == sort ? AppColors.primaryBright : AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: option == sort ? AppColors.primaryBright : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert_rounded, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('Trier', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
