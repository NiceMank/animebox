import 'package:flutter/material.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/library_entry.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_title.dart';
import '../../shared/widgets/status_pill.dart';

/// Écran Bibliothèque : favoris et animés suivis.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.repository, required this.onExplore});

  final AnimeRepository repository;
  final VoidCallback onExplore;

  static const SliverGridDelegateWithFixedCrossAxisCount _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    mainAxisSpacing: 14,
    crossAxisSpacing: 12,
    childAspectRatio: 0.5,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (BuildContext context, Widget? child) {
        final List<LibraryEntry> favorites = repository.libraryEntries.where((LibraryEntry entry) => entry.isFavorite).toList();
        final List<Anime> followed = repository.allAnime.where((Anime anime) => anime.isFollowing).toList();

        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            key: const PageStorageKey<String>('library-scroll'),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
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
                      const SizedBox(width: 10),
                      StatusPill('${repository.libraryEntries.length} animés', color: AppColors.primaryBright),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SectionTitle(title: '❤️ Favoris')),
              if (favorites.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: EmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: 'Aucun favori',
                      message: 'Appuyez sur le cœur d\'un animé pour le retrouver ici.',
                      actionLabel: 'Explorer',
                      onAction: onExplore,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverGrid.builder(
                    gridDelegate: _gridDelegate,
                    itemCount: favorites.length,
                    itemBuilder: (BuildContext context, int index) {
                      final LibraryEntry entry = favorites[index];
                      return AnimeCard(
                        anime: entry.anime,
                        progress: entry.resumeFraction(),
                        onTap: () => Navigator.of(context).pushNamed(AppRoutes.animeDetails, arguments: AnimeIdArgs(entry.anime.id)),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SectionTitle(title: '✨ Suivis')),
              if (followed.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: EmptyState(
                      icon: Icons.add_task_rounded,
                      title: 'Aucun animé suivi',
                      message: 'Suivez un animé depuis sa fiche pour être prévenu des nouveautés.',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverGrid.builder(
                    gridDelegate: _gridDelegate,
                    itemCount: followed.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Anime anime = followed[index];
                      return AnimeCard(
                        anime: anime,
                        onTap: () => Navigator.of(context).pushNamed(AppRoutes.animeDetails, arguments: AnimeIdArgs(anime.id)),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        );
      },
    );
  }
}
