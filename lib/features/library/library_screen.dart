import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../anime/data/models/anime.dart';
import '../anime/data/models/episode.dart';
import '../anime/data/models/library_entry.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../app/router.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/poster_image.dart';
import 'services/library_service.dart';
import '../home/widgets/continue_card.dart';
import 'widgets/followed_card.dart';
import 'widgets/recent_episode_card.dart';

/// Catégories de la bibliothèque.
enum LibraryCategory {
  favorites('Favoris', Icons.favorite_rounded),
  followed('Suivis', Icons.favorite_outline_rounded),
  continueWatching('Continuer', Icons.play_circle_outline_rounded),
  recent('Récemment ajoutés', Icons.fiber_new_rounded),
  all('Tous les animés', Icons.grid_view_rounded);

  const LibraryCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Tri de la bibliothèque.
enum LibrarySort {
  recentAdded('Plus récemment ajouté', Icons.schedule_rounded),
  nameAsc('Nom A → Z', Icons.sort_by_alpha_rounded),
  nameDesc('Nom Z → A', Icons.sort_by_alpha_rounded),
  episodeCount('Nombre d\'épisodes', Icons.format_list_numbered_rounded),
  latestEpisode('Dernier épisode', Icons.new_releases_outlined);

  const LibrarySort(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Écran 9 — Bibliothèque personnelle : favoris, suivis, continuer,
/// récemment ajoutés et tous les animés, avec tri et vue grille/liste.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.repository, required this.libraryService});

  final AnimeRepository repository;
  final LibraryService libraryService;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryCategory _category = LibraryCategory.favorites;
  LibrarySort _sort = LibrarySort.recentAdded;
  bool _gridView = true;

  void _openAnime(String animeId) {
    Navigator.of(context).pushNamed(AppRoutes.animeDetails, arguments: AnimeIdArgs(animeId));
  }

  void _openResume(LibraryEntry entry) {
    final Episode? episode = entry.resumeEpisode;
    if (episode == null) {
      _openAnime(entry.anime.id);
      return;
    }
    Navigator.of(context).pushNamed(
      AppRoutes.player,
      arguments: EpisodeRouteArgs(animeId: entry.anime.id, episodeId: episode.id),
    );
  }

  void _openRecent(Anime anime) {
    final Episode? episode = anime.latestEpisode;
    if (episode == null) {
      _openAnime(anime.id);
      return;
    }
    Navigator.of(context).pushNamed(
      AppRoutes.episodeQuality,
      arguments: EpisodeRouteArgs(animeId: anime.id, episodeId: episode.id),
    );
  }

  int _compare(Anime a, Anime b) {
    switch (_sort) {
      case LibrarySort.recentAdded:
        final int aIndex = widget.repository.recentEpisodeIds.indexOf(a.id);
        final int bIndex = widget.repository.recentEpisodeIds.indexOf(b.id);
        final int aRank = aIndex == -1 ? 999 : aIndex;
        final int bRank = bIndex == -1 ? 999 : bIndex;
        return aRank.compareTo(bRank);
      case LibrarySort.nameAsc:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySort.nameDesc:
        return b.title.toLowerCase().compareTo(a.title.toLowerCase());
      case LibrarySort.episodeCount:
        return b.totalEpisodes.compareTo(a.totalEpisodes);
      case LibrarySort.latestEpisode:
        final DateTime aDate = a.latestEpisode?.date ?? DateTime(1970);
        final DateTime bDate = b.latestEpisode?.date ?? DateTime(1970);
        return bDate.compareTo(aDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LibraryService service = widget.libraryService;
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (BuildContext context, Widget? child) {
        return SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Bibliothèque',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    _IconToggle(
                      tooltip: _gridView ? 'Passer en liste' : 'Passer en grille',
                      icon: _gridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                      onTap: () => setState(() => _gridView = !_gridView),
                    ),
                    const SizedBox(width: 6),
                    _SortButton(sort: _sort, onChanged: (LibrarySort sort) => setState(() => _sort = sort)),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                  scrollDirection: Axis.horizontal,
                  itemCount: LibraryCategory.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final LibraryCategory category = LibraryCategory.values[index];
                    final bool selected = category == _category;
                    return InkWell(
                      onTap: () => setState(() => _category = category),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: selected ? const LinearGradient(colors: AppColors.primaryGradient) : null,
                          color: selected ? null : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selected ? Colors.transparent : AppColors.divider),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              category.icon,
                              size: 15,
                              color: selected ? Colors.white : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              category.label,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: selected ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(child: _buildContent(service)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(LibraryService service) {
    switch (_category) {
      case LibraryCategory.favorites:
        return _buildAnimeList(service.favorites.map((LibraryEntry entry) => entry.anime).toList());
      case LibraryCategory.followed:
        return _buildFollowed(service.followedAnime);
      case LibraryCategory.continueWatching:
        return _buildContinue(service.continueWatching);
      case LibraryCategory.recent:
        return _buildRecent(service.recentlyAdded);
      case LibraryCategory.all:
        return _buildAnimeList(service.allAnime);
    }
  }

  /// Grille ou liste d'animés (favoris / tous), triés.
  Widget _buildAnimeList(List<Anime> anime) {
    if (anime.isEmpty) {
      return EmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'Aucun favori',
        message: 'Appuyez sur le cœur d\'un animé pour le retrouver ici.',
      );
    }
    final List<Anime> sorted = List.of(anime)..sort(_compare);

    if (_gridView) {
      return GridView.builder(
        key: const PageStorageKey<String>('library-grid'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 14,
          childAspectRatio: 0.58,
        ),
        itemCount: sorted.length,
        itemBuilder: (BuildContext context, int index) => AnimeCard(
          anime: sorted[index],
          onTap: () => _openAnime(sorted[index].id),
        ),
      );
    }

    return ListView.separated(
      key: const PageStorageKey<String>('library-list'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final Anime anime = sorted[index];
        return Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => _openAnime(anime.id),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  PosterImage(asset: anime.posterAsset, url: anime.posterUrl, width: 46, height: 64, borderRadius: 10, fallbackLabel: anime.title),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(anime.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 3),
                        Text(anime.episodeMeta, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(
                          anime.genres.take(2).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFollowed(List<Anime> followed) {
    if (followed.isEmpty) {
      return const EmptyState(
        icon: Icons.add_task_rounded,
        title: 'Aucun animé suivi',
        message: 'Suivez un animé depuis sa fiche pour être prévenu des nouveautés.',
      );
    }
    return ListView.separated(
      key: const PageStorageKey<String>('library-followed'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      itemCount: followed.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) => FollowedCard(
        anime: followed[index],
        onTap: () => _openAnime(followed[index].id),
      ),
    );
  }

  Widget _buildContinue(List<LibraryEntry> entries) {
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.play_circle_outline_rounded,
        title: 'Rien à reprendre',
        message: 'Commencez un épisode dans le lecteur pour le retrouver ici.',
      );
    }
    return ListView.separated(
      key: const PageStorageKey<String>('library-continue'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) => ContinueCard(
        entry: entries[index],
        onTap: () => _openResume(entries[index]),
      ),
    );
  }

  Widget _buildRecent(List<Anime> anime) {
    if (anime.isEmpty) {
      return const EmptyState(
        icon: Icons.fiber_new_rounded,
        title: 'Aucun nouvel épisode',
        message: 'Les épisodes détectés par la synchronisation apparaîtront ici.',
      );
    }
    return ListView.separated(
      key: const PageStorageKey<String>('library-recent'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      itemCount: anime.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) => RecentEpisodeCard(
        anime: anime[index],
        onTap: () => _openRecent(anime[index]),
      ),
    );
  }
}

class _IconToggle extends StatelessWidget {
  const _IconToggle({required this.tooltip, required this.icon, required this.onTap});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 20, color: AppColors.textSecondary),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.divider),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onChanged});

  final LibrarySort sort;
  final ValueChanged<LibrarySort> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LibrarySort>(
      tooltip: 'Trier la bibliothèque',
      onSelected: onChanged,
      color: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (BuildContext context) => [
        for (final LibrarySort option in LibrarySort.values)
          PopupMenuItem<LibrarySort>(
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
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
