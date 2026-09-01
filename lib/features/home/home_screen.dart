import 'package:flutter/material.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/library_entry.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../anime/data/repositories/catalog_repository.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/section_title.dart';
import 'widgets/continue_card.dart';
import 'widgets/hero_carousel.dart';
import 'widgets/release_card.dart';

/// Écran d'accueil : carousel, nouveaux épisodes, mes animés, continuer.
///
/// Les sections ne sont JAMAIS codées en dur dans l'interface : elles sont
/// alimentées par le dépôt (catalogue backend en mode API, données de
/// démonstration sinon). Le dépôt étant un [Listenable], l'écran réagit aux
/// chargements, à la mise à jour des métadonnées et au passage hors-ligne.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.onSearchTap,
    required this.onLibraryTap,
  });

  final AnimeRepository repository;
  final VoidCallback onSearchTap;
  final VoidCallback onLibraryTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: repository,
        builder: (BuildContext context, Widget? child) {
          final List<Anime> releases = repository.latestReleases;
          final List<LibraryEntry> favorites =
              repository.libraryEntries.where((LibraryEntry entry) => entry.isFavorite).toList();
          final List<LibraryEntry> watching =
              repository.libraryEntries.where((LibraryEntry entry) => entry.hasProgress).toList();
          final CatalogRepository? catalog = repository is CatalogRepository ? repository as CatalogRepository : null;

          return CustomScrollView(
            key: const PageStorageKey<String>('home-scroll'),
            slivers: [
              SliverToBoxAdapter(child: _HomeTopBar(onSearchTap: onSearchTap)),
              if (catalog != null) SliverToBoxAdapter(child: _CatalogStatusBanner(catalog: catalog)),
              SliverToBoxAdapter(child: HeroCarousel(repository: repository)),
              const SliverToBoxAdapter(child: SectionTitle(title: 'Nouveaux épisodes', icon: Icons.local_fire_department_rounded)),
              if (catalog != null && catalog.isLoadingCatalog && releases.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: _CatalogLoading(),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 160,
                    child: ListView.separated(
                      key: const PageStorageKey<String>('home-releases'),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      scrollDirection: Axis.horizontal,
                      itemCount: releases.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (BuildContext context, int index) => ReleaseCard(
                        anime: releases[index],
                        onTap: () => Navigator.of(context).pushNamed(
                          AppRoutes.animeDetails,
                          arguments: AnimeIdArgs(releases[index].id),
                        ),
                      ),
                    ),
                  ),
                ),
          SliverToBoxAdapter(child: SectionTitle(title: 'Mes animés', icon: Icons.star_rounded, actionLabel: 'Tout voir', onAction: onLibraryTap)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 240,
              child: favorites.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text('Aucun favori pour le moment.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ),
                    )
                  : ListView.separated(
                      key: const PageStorageKey<String>('home-favorites'),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      scrollDirection: Axis.horizontal,
                      itemCount: favorites.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (BuildContext context, int index) {
                        final LibraryEntry entry = favorites[index];
                        return AnimeCard(
                          anime: entry.anime,
                          width: 118,
                          progress: entry.resumeFraction(),
                          onTap: () => Navigator.of(context).pushNamed(
                            AppRoutes.animeDetails,
                            arguments: AnimeIdArgs(entry.anime.id),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SliverToBoxAdapter(child: SectionTitle(title: 'Continuer', icon: Icons.play_circle_outline_rounded)),
          if (watching.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text('Commencez un épisode pour le retrouver ici.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverList.separated(
                itemCount: watching.length,
                itemBuilder: (BuildContext context, int index) {
                  final LibraryEntry entry = watching[index];
                  return ContinueCard(
                    entry: entry,
                    onTap: () => Navigator.of(context).pushNamed(
                      AppRoutes.animeDetails,
                      arguments: AnimeIdArgs(entry.anime.id),
                    ),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 12),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
          );
        },
      ),
    );
  }
}

/// Bandeau d'état du catalogue : récupération en cours, hors-ligne
/// (dernières données connues) ou actualisation impossible.
class _CatalogStatusBanner extends StatelessWidget {
  const _CatalogStatusBanner({required this.catalog});

  final CatalogRepository catalog;

  @override
  Widget build(BuildContext context) {
    if (!catalog.isOffline) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Hors-ligne — dernières données connues affichées.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => catalog.refreshCatalog(),
            child: const Text('Réessayer', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Indicateur de récupération du catalogue (premier chargement).
class _CatalogLoading extends StatelessWidget {
  const _CatalogLoading();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBright),
        ),
        const SizedBox(width: 12),
        Text(
          'Récupération du catalogue…',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({required this.onSearchTap});

  final VoidCallback onSearchTap;

  void _showInfoSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: AppColors.primaryGradient),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.movie_filter_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text('AnimeBox', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Étape 1 — fondations de l\'application.\n'
                'La connexion Telegram, la synchronisation des canaux et la lecture arrivent dans les prochaines étapes.',
                style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              const Text('v0.1.0', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Menu',
            onPressed: () => _showInfoSheet(context),
            icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 4),
          const Expanded(child: _Logo()),
          IconButton(
            tooltip: 'Rechercher',
            onPressed: onSearchTap,
            icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ShaderMask(
        shaderCallback: (Rect bounds) => const LinearGradient(colors: AppColors.accentGradient).createShader(bounds),
        child: const Text(
          'ANIMEBOX',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: Colors.white),
        ),
      ),
    );
  }
}
