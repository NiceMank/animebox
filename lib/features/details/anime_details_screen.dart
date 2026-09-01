import 'package:flutter/material.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/episode.dart';
import '../anime/data/models/library_entry.dart';
import '../anime/data/models/metadata_status.dart';
import '../anime/data/models/season.dart';
import '../anime/data/models/video_quality.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../anime/data/repositories/catalog_repository.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/episode_card.dart';
import '../../shared/widgets/favorite_button.dart';
import '../../shared/widgets/poster_image.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/status_pill.dart';
import 'widgets/metadata_review_sheet.dart';

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
  /// Recharge la fiche complète après une action d'administration
  /// (correction manuelle) : les saisons/épisodes reflètent le backend.
  Future<void> _refreshDetail() async {
    if (widget.repository case final CatalogRepository catalog) {
      await catalog.refreshAnime(widget.animeId);
      if (mounted) setState(() {});
    }
  }

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
            _EpisodesTab(
              anime: anime,
              onEpisodeTap: (Season season, Episode episode) {
                Navigator.of(context).pushNamed(
                  AppRoutes.animeEpisodes,
                  arguments: EpisodeListArgs(anime.id, seasonId: season.id),
                );
              },
            ),
            _DetailsTab(anime: anime, repository: widget.repository, onAnimeChanged: _refreshDetail),
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
            PosterImage(asset: anime.backdropAsset, url: anime.backdropUrl, borderRadius: 0, fallbackLabel: anime.title),
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
    final bool started = (entry?.resumePosition ?? Duration.zero) > Duration.zero;

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
///
/// Un appui sur un épisode ouvre la liste complète des épisodes de la
/// saison (écran 4).
class _EpisodesTab extends StatelessWidget {
  const _EpisodesTab({required this.anime, required this.onEpisodeTap});

  final Anime anime;
  final void Function(Season season, Episode episode) onEpisodeTap;

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
            for (final Episode episode in season.episodes.reversed.take(3)) ...[
              EpisodeCard(
                episode: episode,
                onTap: () => onEpisodeTap(season, episode),
              ),
              const SizedBox(height: 8),
            ],
            if (season.episodes.length > 3) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () {
                    final Episode first = season.episodes.first;
                    onEpisodeTap(season, first);
                  },
                  child: Text(
                    'Voir les ${season.episodeCount} épisodes',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primaryBright),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

/// Onglet Détails : synopsis, fiche technique enrichie par les métadonnées
/// du catalogue, états d'enrichissement et actions d'administration.
class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.anime,
    required this.repository,
    required this.onAnimeChanged,
  });

  final Anime anime;
  final AnimeRepository repository;
  final VoidCallback onAnimeChanged;

  static String _formatFollowers(int followers) {
    if (followers >= 1000000) return '${(followers / 1000000).toStringAsFixed(1)} M';
    if (followers >= 1000) return '${(followers / 1000).toStringAsFixed(0)} K';
    return '$followers';
  }

  CatalogRepository? get _catalog =>
      repository is CatalogRepository ? repository as CatalogRepository : null;

  String get _episodeAvailability {
    // « X/24 disponibles » : épisodes réellement publiés sur Telegram
    // rapportés au total annoncé par le fournisseur (jamais inventé).
    final int available = anime.totalEpisodes;
    final int announced = anime.totalEpisodesAnnounced;
    if (announced > 0 && announced != available) return '$available / $announced';
    return '$available';
  }

  void _openMetadataReview(BuildContext context) {
    final CatalogRepository? catalog = _catalog;
    if (catalog == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (BuildContext context) => MetadataReviewSheet(
        anime: anime,
        catalog: catalog,
        onAnimeChanged: onAnimeChanged,
      ),
    );
  }

  Future<void> _refreshMetadata(BuildContext context) async {
    final CatalogRepository? catalog = _catalog;
    if (catalog == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Actualisation des métadonnées…')),
    );
    final bool ok = await catalog.refreshAnimeMetadata(anime.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Métadonnées mises à jour.' : 'Actualisation impossible pour le moment.'),
      ),
    );
    onAnimeChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey<String>('details-tab'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
      children: [
        _MetadataStatusBanner(
          anime: anime,
          onReview: () => _openMetadataReview(context),
        ),
        const SizedBox(height: 12),
        const Text('Synopsis', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(
          anime.description.isEmpty ? 'Informations en attente.' : anime.description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
        ),
        const SizedBox(height: 24),
        const Text('Informations', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        _InfoRow(label: 'Année', value: anime.year > 0 ? '${anime.year}' : '—'),
        _InfoRow(label: 'Durée', value: '${anime.episodeDurationMin} min/ép'),
        if (anime.rating > 0) _InfoRow(label: 'Note', value: anime.rating.toStringAsFixed(1)),
        _InfoRow(label: 'Saisons', value: '${anime.seasons.length}'),
        _InfoRow(label: 'Épisodes', value: _episodeAvailability),
        _InfoRow(label: 'Genres', value: anime.genres.isEmpty ? '—' : anime.genres.join(', ')),
        _InfoRow(label: 'Langues', value: anime.languages.join(', ')),
        _InfoRow(label: 'Source', value: anime.source),
        _InfoRow(label: 'Qualités', value: anime.availableQualities.map((quality) => quality.label).join(', ')),
        if (anime.originalTitle != null && anime.originalTitle != anime.title)
          _InfoRow(label: 'Titre original', value: anime.originalTitle!),
        if (anime.alternativeTitles.isNotEmpty)
          _InfoRow(label: 'Autres titres', value: anime.alternativeTitles.join(', ')),
        if (anime.metadataSource != null && anime.metadataStatus == MetadataStatus.found)
          _InfoRow(
            label: 'Métadonnées',
            value: 'Enrichi par ${anime.metadataSource}'
                '${anime.metadataUpdatedAt != null ? ' · mis à jour le ${anime.metadataUpdatedAt!.substring(0, 10)}' : ''}',
          ),
        if (anime.followers > 0) _InfoRow(label: 'Abonnés', value: _formatFollowers(anime.followers)),
        const SizedBox(height: 20),
        if (_catalog != null)
          PrimaryButton(
            label: 'Actualiser les métadonnées',
            icon: Icons.sync_rounded,
            outlined: true,
            onTap: () => _refreshMetadata(context),
          ),
      ],
    );
  }
}

/// Bandeau d'état de l'enrichissement : fiche complète, correspondance
/// incertaine (revue) ou informations en attente (fiche minimale).
class _MetadataStatusBanner extends StatelessWidget {
  const _MetadataStatusBanner({required this.anime, this.onReview});

  final Anime anime;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String title, String message, String? action) =
        switch (anime.metadataStatus) {
      MetadataStatus.reviewRequired => (
          Icons.help_outline_rounded,
          AppColors.warning,
          'Correspondance à vérifier',
          'Ce titre ressemble à une fiche connue sans certitude. '
              'Vérifiez la bonne association avant de continuer.',
          'Corriger',
        ),
      MetadataStatus.pending || MetadataStatus.notFound => (
          Icons.hourglass_empty_rounded,
          AppColors.textMuted,
          'Informations en attente',
          'Aucune métadonnée fiable pour cette fiche. '
              'Le contenu Telegram reste disponible tel quel.',
          null,
        ),
      MetadataStatus.ignored => (
          Icons.block_rounded,
          AppColors.textMuted,
          'Revue fermée',
          'Cette fiche a été ignorée lors de la correction manuelle.',
          null,
        ),
      _ => (Icons.check_circle_outline_rounded, AppColors.success, 'Fiche enrichie', '', null),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(message, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          if (action != null && onReview != null)
            TextButton(
              onPressed: onReview,
              child: Text(action, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
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
