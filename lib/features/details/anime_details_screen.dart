import 'package:flutter/material.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/episode.dart';
import '../anime/data/models/library_entry.dart';
import '../anime/data/models/season.dart';
import '../anime/data/models/video_quality.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/episode_card.dart';
import '../../shared/widgets/favorite_button.dart';
import '../../shared/widgets/poster_image.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/status_pill.dart';

/// Fiche d'un animé : en-tête visuel, actions (Favoris / Reprendre / Suivre)
/// et onglets Épisodes / Détails.
class AnimeDetailsScreen extends StatefulWidget {
  const AnimeDetailsScreen({super.key, required this.repository, required this.animeId});

  final AnimeRepository repository;
  final String animeId;

  @override
  State<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends State<AnimeDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    if (widget.repository.byId(widget.animeId) == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.error_outline_rounded, title: 'Animé introuvable'),
      );
    }
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: widget.repository,
        builder: (BuildContext context, Widget? child) {
          final Anime anime = widget.repository.byId(widget.animeId)!;
          return _buildScaffold(context, anime);
        },
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, Anime anime) {
    final LibraryEntry? entry = widget.repository.libraryEntryFor(anime.id);
    final bool isFavorite = entry?.isFavorite ?? false;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) => [
          _buildAppBar(context, anime),
          SliverToBoxAdapter(child: _buildInfoBlock(context, anime, isFavorite, entry)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTabBarDelegate(
              TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.primaryGradient),
                  borderRadius: BorderRadius.circular(14),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                dividerColor: Colors.transparent,
                tabs: const [Tab(text: 'Épisodes'), Tab(text: 'Détails')],
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _EpisodesTab(anime: anime),
            _DetailsTab(anime: anime),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, Anime anime) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 340,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Retour',
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            PosterImage(asset: anime.backdropAsset, borderRadius: 0, fallbackLabel: anime.title),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 0.75, 1.0],
                  colors: [Colors.transparent, Color(0x660A0817), AppColors.background],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 14,
              child: Text(
                anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      shadows: const [Shadow(color: Colors.black45, blurRadius: 10)],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBlock(BuildContext context, Anime anime, bool isFavorite, LibraryEntry? entry) {
    final bool started = (entry?.progress ?? 0) > 0;

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: anime.episodeMeta),
              _MetaChip(label: '${anime.year}'),
              _MetaChip(label: '${anime.episodeDurationMin} min/ép'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FavoriteButton(
                isFavorite: isFavorite,
                onTap: () => widget.repository.toggleFavorite(anime.id),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: started ? 'Reprendre' : 'Commencer',
                  icon: Icons.play_arrow_rounded,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('La lecture arrive dans une prochaine étape.')),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PrimaryButton(
                label: anime.isFollowing ? 'Suivi' : 'Suivre',
                icon: anime.isFollowing ? Icons.check_rounded : Icons.add_rounded,
                outlined: true,
                expanded: false,
                onTap: () => widget.repository.toggleFollow(anime.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  _StickyTabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => 62;

  @override
  double get maxExtent => 62;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) => oldDelegate.tabBar != tabBar;
}

/// Onglet Épisodes : liste des saisons (de la plus récente à la plus
/// ancienne) avec leurs épisodes et qualités disponibles.
class _EpisodesTab extends StatelessWidget {
  const _EpisodesTab({required this.anime});

  final Anime anime;

  @override
  Widget build(BuildContext context) {
    final List<Season> seasons = anime.seasons.reversed.toList();
    return ListView.builder(
      key: const PageStorageKey<String>('episodes-tab'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
      itemCount: seasons.length,
      itemBuilder: (BuildContext context, int index) {
        final Season season = seasons[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Saison ${season.number}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(width: 8),
                StatusPill('${season.episodeCount} ép.', color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 10),
            for (final Episode episode in season.episodes.reversed) ...[
              EpisodeCard(
                episode: episode,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lecture et téléchargement : prochaine étape.')),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

/// Onglet Détails : synopsis et fiche technique.
class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.anime});

  final Anime anime;

  static String _formatFollowers(int followers) {
    if (followers >= 1000000) return '${(followers / 1000000).toStringAsFixed(1)} M';
    if (followers >= 1000) return '${(followers / 1000).toStringAsFixed(0)} K';
    return '$followers';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey<String>('details-tab'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
      children: [
        const Text('Synopsis', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(anime.description, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55)),
        const SizedBox(height: 24),
        const Text('Informations', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        _InfoRow(label: 'Année', value: '${anime.year}'),
        _InfoRow(label: 'Durée', value: '${anime.episodeDurationMin} min/ép'),
        _InfoRow(label: 'Saisons', value: '${anime.seasons.length}'),
        _InfoRow(label: 'Épisodes', value: '${anime.totalEpisodes}'),
        _InfoRow(label: 'Genres', value: anime.genres.join(', ')),
        _InfoRow(label: 'Langues', value: anime.languages.join(', ')),
        _InfoRow(label: 'Source', value: anime.source),
        _InfoRow(label: 'Qualités', value: anime.availableQualities.map((quality) => quality.label).join(', ')),
        if (anime.followers > 0) _InfoRow(label: 'Abonnés', value: _formatFollowers(anime.followers)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
