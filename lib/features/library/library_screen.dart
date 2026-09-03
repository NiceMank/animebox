import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../anime/data/models/anime.dart';
import '../anime/data/models/episode.dart';
import '../anime/data/models/library_entry.dart';
import '../anime/data/models/playback_progress.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../app/router.dart';
import '../local/data/local_database.dart';
import '../media/models/download_models.dart';
import '../media/services/download_manager.dart';
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
  history('Historique', Icons.history_rounded),
  downloaded('Téléchargés', Icons.download_done_rounded),
  all('Tous les animés', Icons.grid_view_rounded);

  const LibraryCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Tri de la bibliothèque (prompt 10 §2 — toutes les options réelles).
enum LibrarySort {
  recentAdded('Plus récemment ajouté', Icons.schedule_rounded),
  updated('Récemment mis à jour', Icons.update_rounded),
  nameAsc('Nom A → Z', Icons.sort_by_alpha_rounded),
  nameDesc('Nom Z → A', Icons.sort_by_alpha_rounded),
  episodeCount('Nombre d\'épisodes', Icons.format_list_numbered_rounded),
  latestEpisode('Dernier épisode', Icons.new_releases_outlined),
  progress('Progression', Icons.trending_up_rounded),
  favorites('Favoris', Icons.favorite_rounded);

  const LibrarySort(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Filtres combinables de la vue « Tous les animés » (prompt 10 §6).
enum LibraryFilter {
  favorites('Favoris', Icons.favorite_rounded),
  inProgress('En cours', Icons.play_circle_outline_rounded),
  completed('Terminés', Icons.check_circle_outline_rounded),
  notStarted('Non commencés', Icons.radio_button_unchecked_rounded),
  downloaded('Téléchargés', Icons.download_done_rounded),
  novelties('Nouveautés', Icons.fiber_new_rounded);

  const LibraryFilter(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Écran Bibliothèque : parcours, recherche, tri, filtres combinables,
/// favoris, historique réel, téléchargements et nouveautés — tout est lu
/// depuis les données locales réelles (prompt 10).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.libraryService,
    this.downloadManager,
    this.database,
  });

  final AnimeRepository repository;
  final LibraryService libraryService;

  /// Gestionnaire de téléchargements réel (optionnel : absent en tests UI).
  final DownloadManager? downloadManager;

  /// Base locale pour la persistance des préférences d'affichage
  /// (tri/filtres/vue grille — prompt 10 §27 ; optionnelle).
  final LocalDatabase? database;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryCategory _category = LibraryCategory.favorites;
  LibrarySort _sort = LibrarySort.recentAdded;
  final Set<LibraryFilter> _filters = <LibraryFilter>{};
  bool _gridView = true;

  static const String _prefsKey = 'library_ui';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  // -----------------------------------------------------------------------
  // Persistance des préférences d'affichage (§27 — survit au redémarrage).
  // -----------------------------------------------------------------------

  Future<void> _loadPrefs() async {
    final LocalDatabase? db = widget.database;
    if (db == null) return;
    try {
      final String? raw = await db.getSetting(_prefsKey);
      if (raw != null) {
        final Map<String, Object?> prefs = (jsonDecode(raw) as Map).cast<String, Object?>();
        _sort = LibrarySort.values.firstWhere(
          (LibrarySort s) => s.name == prefs['sort'],
          orElse: () => LibrarySort.recentAdded,
        );
        _gridView = prefs['grid'] != false;
        final List<Object?> rawFilters = (prefs['filters'] as List<Object?>? ?? const []);
        _filters
          ..clear()
          ..addAll([
            for (final Object? name in rawFilters)
              if (LibraryFilter.values.any((LibraryFilter f) => f.name == name))
                LibraryFilter.values.firstWhere((LibraryFilter f) => f.name == name),
          ]);
      }
    } catch (_) {
      // Réglages absents/corrompus : valeurs par défaut.
    }
  }

  void _savePrefs() {
    final LocalDatabase? db = widget.database;
    if (db == null) return;
    final String value = jsonEncode({
      'sort': _sort.name,
      'grid': _gridView,
      'filters': [for (final LibraryFilter f in _filters) f.name],
    });
    db.setSetting(_prefsKey, value).catchError((_) => true);
  }

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

  /// Reprend la lecture d'un épisode de l'historique (données réelles).
  void _openFromHistory(PlaybackProgress item) {
    Navigator.of(context).pushNamed(
      AppRoutes.player,
      arguments: EpisodeRouteArgs(animeId: item.animeId, episodeId: item.episodeId),
    );
  }

  // -----------------------------------------------------------------------
  // Helpers — informations réelles (jamais inventées).
  // -----------------------------------------------------------------------

  /// Retrouve l'épisode et sa saison dans le catalogue local (ou null).
  (Episode, int)? _episodeInfo(String animeId, String episodeId) {
    final Anime? anime = widget.repository.byId(animeId);
    if (anime == null) return null;
    for (int si = 0; si < anime.seasons.length; si++) {
      for (final Episode episode in anime.seasons[si].episodes) {
        if (episode.id == episodeId) return (episode, anime.seasons[si].number);
      }
    }
    return null;
  }

  /// Ids d'animés ayant au moins un téléchargement terminé (réel).
  Set<String> get _downloadedAnimeIds => {
        for (final DownloadTask task in widget.downloadManager?.tasks ?? const <DownloadTask>[])
          if (task.status == DownloadStatus.completed) task.animeId,
      };

  /// Dernier visionnage par animé (pour le tri « mis à jour »).
  Map<String, DateTime> get _lastPlayedAtByAnime {
    final Map<String, DateTime> result = {};
    for (final PlaybackProgress item in widget.repository.watchHistory) {
      final DateTime? best = result[item.animeId];
      if (best == null || item.savedAt.isAfter(best)) result[item.animeId] = item.savedAt;
    }
    return result;
  }

  /// Volume de visionnage réel d'un animé (0..1) : somme des positions /
  /// durée totale des épisodes détectés (jamais inventée).
  double _watchVolume(Anime anime) {
    final LibraryEntry? entry = widget.repository.libraryEntryFor(anime.id);
    if (entry == null || anime.totalEpisodes == 0) return 0;
    final int totalMs = anime.totalEpisodes * Duration(minutes: anime.episodeDurationMin.toInt()).inMilliseconds;
    if (totalMs <= 0) return 0;
    final int watchedMs = entry.progressMap.values.fold(0, (int sum, Duration d) => sum + d.inMilliseconds);
    return (watchedMs / totalMs).clamp(0.0, 1.0);
  }

  bool _allStartedCompleted(Anime anime) {
    final LibraryEntry? entry = widget.repository.libraryEntryFor(anime.id);
    if (entry == null || entry.progressMap.isEmpty) return false;
    for (final MapEntry<String, Duration> item in entry.progressMap.entries) {
      if (item.value > Duration.zero && !widget.repository.episodeCompleted(anime.id, item.key)) return false;
    }
    return entry.progressMap.values.any((Duration d) => d > Duration.zero);
  }

  // -----------------------------------------------------------------------
  // Tri (§2) — toutes les options s'appuient sur des données réelles.
  // -----------------------------------------------------------------------

  int _compare(Anime a, Anime b) {
    switch (_sort) {
      case LibrarySort.recentAdded:
        final List<String> recents = widget.repository.recentEpisodeIds;
        final int aRank = recents.indexOf(a.id);
        final int bRank = recents.indexOf(b.id);
        return (aRank == -1 ? 999 : aRank).compareTo(bRank == -1 ? 999 : bRank);
      case LibrarySort.updated:
        final Map<String, DateTime> last = _lastPlayedAtByAnime;
        final DateTime aDate = last[a.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime bDate = last[b.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        final int byDate = bDate.compareTo(aDate);
        return byDate != 0 ? byDate : a.title.toLowerCase().compareTo(b.title.toLowerCase());
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
      case LibrarySort.progress:
        return _watchVolume(b).compareTo(_watchVolume(a));
      case LibrarySort.favorites:
        final bool aFav = widget.repository.libraryEntryFor(a.id)?.isFavorite ?? false;
        final bool bFav = widget.repository.libraryEntryFor(b.id)?.isFavorite ?? false;
        if (aFav != bFav) return aFav ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
  }

  /// Filtres COMBINABLES appliqués à la vue « Tous » (§6).
  List<Anime> _applyFilters(List<Anime> anime) {
    if (_filters.isEmpty) return anime;
    final Set<String> downloaded = _downloadedAnimeIds;
    final Set<String> novelties = widget.repository.recentEpisodeIds.toSet();
    return [
      for (final Anime item in anime)
        if (_matchesAllFilters(item, downloaded, novelties)) item,
    ];
  }

  bool _matchesAllFilters(Anime anime, Set<String> downloaded, Set<String> novelties) {
    final LibraryEntry? entry = widget.repository.libraryEntryFor(anime.id);
    for (final LibraryFilter filter in _filters) {
      final bool ok = switch (filter) {
        LibraryFilter.favorites => entry?.isFavorite ?? false,
        LibraryFilter.inProgress => entry?.hasProgress ?? false,
        LibraryFilter.completed => _allStartedCompleted(anime),
        LibraryFilter.notStarted => !(entry?.hasProgress ?? false),
        LibraryFilter.downloaded => downloaded.contains(anime.id),
        LibraryFilter.novelties => novelties.contains(anime.id),
      };
      if (!ok) return false;
    }
    return true;
  }

  // -----------------------------------------------------------------------
  // Construction de l'interface
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final LibraryService service = widget.libraryService;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.repository, widget.downloadManager]),
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
                      onTap: () {
                        setState(() => _gridView = !_gridView);
                        _savePrefs();
                      },
                    ),
                    const SizedBox(width: 6),
                    _SortButton(
                      sort: _sort,
                      onChanged: (LibrarySort sort) {
                        setState(() => _sort = sort);
                        _savePrefs();
                      },
                    ),
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
                    return _Chip(
                      label: category.label,
                      icon: category.icon,
                      selected: selected,
                      onTap: () => setState(() => _category = category),
                    );
                  },
                ),
              ),
              if (_category == LibraryCategory.all) _buildFilterBar(),
              Expanded(child: _buildContent(service)),
            ],
          ),
        );
      },
    );
  }

  /// Barre des filtres combinables (§6) — vue « Tous les animés ».
  Widget _buildFilterBar() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        scrollDirection: Axis.horizontal,
        itemCount: LibraryFilter.values.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return _Chip(
              label: 'Toutes les séries',
              icon: Icons.select_all_rounded,
              selected: _filters.isEmpty,
              compact: true,
              onTap: () {
                setState(() => _filters.clear());
                _savePrefs();
              },
            );
          }
          final LibraryFilter filter = LibraryFilter.values[index - 1];
          return _Chip(
            label: filter.label,
            icon: filter.icon,
            selected: _filters.contains(filter),
            compact: true,
            onTap: () {
              setState(() {
                if (_filters.contains(filter)) {
                  _filters.remove(filter);
                } else {
                  _filters.add(filter);
                }
              });
              _savePrefs();
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(LibraryService service) {
    switch (_category) {
      case LibraryCategory.favorites:
        return _buildAnimeList(
          service.favorites.map((LibraryEntry entry) => entry.anime).toList(),
          emptyWidget: EmptyState(
            icon: Icons.favorite_border_rounded,
            title: 'Aucun favori pour le moment.',
            message: 'Marquez vos animés préférés pour les retrouver ici.',
            actionLabel: 'Explorer ma bibliothèque',
            onAction: () => setState(() => _category = LibraryCategory.all),
          ),
        );
      case LibraryCategory.followed:
        return _buildFollowed(service.followedAnime);
      case LibraryCategory.continueWatching:
        return _buildContinue(service.continueWatching);
      case LibraryCategory.recent:
        return _buildRecent(service.recentlyAdded);
      case LibraryCategory.history:
        return _buildHistory();
      case LibraryCategory.downloaded:
        return _buildDownloaded();
      case LibraryCategory.all:
        return _buildAnimeList(
          _applyFilters(service.allAnime),
          emptyWidget: EmptyState(
            icon: Icons.video_library_outlined,
            title: _filters.isEmpty && service.allAnime.isEmpty
                ? 'Votre bibliothèque est encore vide'
                : 'Aucun animé ne correspond aux filtres',
            message: _filters.isEmpty && service.allAnime.isEmpty
                ? 'Synchronisez vos sources Telegram pour faire apparaître vos animés.'
                : 'Modifiez ou combinez différemment les filtres.',
            actionLabel: _filters.isEmpty && service.allAnime.isEmpty ? 'Ajouter une source' : 'Toutes les séries',
            onAction: () {
              if (_filters.isEmpty && service.allAnime.isEmpty) {
                Navigator.of(context).pushNamed(AppRoutes.sourceAdd);
              } else {
                setState(() => _filters.clear());
                _savePrefs();
              }
            },
          ),
        );
    }
  }

  // -----------------------------------------------------------------------
  // Historique réel (§12) — groupé par jour, depuis la base locale.
  // -----------------------------------------------------------------------

  Widget _buildHistory() {
    final List<PlaybackProgress> items = widget.repository.watchHistory;
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'Aucun épisode consulté',
        message: 'Votre historique de visionnage apparaîtra ici.',
      );
    }
    final DateTime now = DateTime.now();
    final Map<String, List<PlaybackProgress>> grouped = {};
    final List<String> order = [];
    for (final PlaybackProgress item in items) {
      final String label = _dayLabel(item.savedAt, now);
      if (!grouped.containsKey(label)) {
        grouped[label] = [];
        order.add(label);
      }
      grouped[label]!.add(item);
    }
    return ListView(
      key: const PageStorageKey<String>('library-history'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _confirmClearHistory,
            icon: const Icon(Icons.delete_sweep_rounded, size: 17, color: AppColors.textSecondary),
            label: const Text('Effacer l\'historique',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ),
        ),
        for (final String day in order) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Text(
              day.toUpperCase(),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted),
            ),
          ),
          for (final PlaybackProgress item in grouped[day]!) _HistoryCard(item: item, onTap: () => _openFromHistory(item), itemInfo: _episodeInfo(item.animeId, item.episodeId), anime: widget.repository.byId(item.animeId)),
        ],
      ],
    );
  }

  String _dayLabel(DateTime date, DateTime now) {
    final DateTime day = DateTime(date.year, date.month, date.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int days = today.difference(day).inDays;
    if (days == 0) return 'Aujourd\'hui';
    if (days == 1) return 'Hier';
    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';
  }

  static String twoDigits(int value) => value.toString().padLeft(2, '0');

  /// Confirmation obligatoire avant effacement (§13) — ne supprime que
  /// l'historique : ni favoris, ni téléchargements, ni sources.
  Future<void> _confirmClearHistory() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Effacer l\'historique ?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16.5, fontWeight: FontWeight.w800)),
        content: const Text(
          'Seul l\'historique de visionnage sera effacé. Vos favoris, téléchargements et sources Telegram sont conservés.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.repository.clearWatchHistory();
      setState(() {});
    }
  }

  // -----------------------------------------------------------------------
  // Téléchargés (§14) — fichiers réellement présents sur l'appareil.
  // -----------------------------------------------------------------------

  Widget _buildDownloaded() {
    final DownloadManager? manager = widget.downloadManager;
    final List<DownloadTask> completed = [
      for (final DownloadTask task in manager?.tasks ?? const <DownloadTask>[])
        if (task.status == DownloadStatus.completed) task,
    ]..sort((DownloadTask a, DownloadTask b) => b.updatedAt.compareTo(a.updatedAt));
    if (manager == null || completed.isEmpty) {
      return const EmptyState(
        icon: Icons.download_done_rounded,
        title: 'Aucun fichier téléchargé',
        message: 'Les épisodes réellement présents sur votre appareil apparaîtront ici.',
      );
    }
    return ListView.separated(
      key: const PageStorageKey<String>('library-downloaded'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      itemCount: completed.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final DownloadTask task = completed[index];
        final Anime? anime = widget.repository.byId(task.animeId);
        return Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            // Le clic OUVRE directement la lecture du fichier local (§14)
            // via la fiche épisode (lecture locale garantie).
            onTap: () => Navigator.of(context).pushNamed(
              AppRoutes.player,
              arguments: EpisodeRouteArgs(animeId: task.animeId, episodeId: task.episodeId),
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  PosterImage(asset: anime?.posterAsset ?? '', url: anime?.posterUrl, width: 40, height: 56, borderRadius: 9, fallbackLabel: task.animeTitle),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.animeTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          'S${twoDigits(task.seasonNumber)}E${twoDigits(task.episodeNumber)}'
                          '${task.qualityLabel != null ? ' • ${task.qualityLabel}' : ''}'
                          '${task.language != null ? ' • ${task.language}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 13, color: AppColors.primaryBright),
                            SizedBox(width: 4),
                            Text('Disponible hors connexion',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primaryBright)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.play_arrow_rounded, color: AppColors.textMuted, size: 22),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Grille ou liste d'animés (favoris / tous), triés.
  Widget _buildAnimeList(List<Anime> anime, {required Widget emptyWidget}) {
    if (anime.isEmpty) return emptyWidget;
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

/// Élément de l'historique : titre, SxxExx (réel), progression réelle.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item, required this.onTap, required this.itemInfo, required this.anime});

  final PlaybackProgress item;
  final VoidCallback onTap;

  /// (Épisode, numéro de saison) retrouvés dans le catalogue local, ou null.
  final (Episode, int)? itemInfo;
  final Anime? anime;

  @override
  Widget build(BuildContext context) {
    final String episodeLabel =
        itemInfo == null ? '' : 'S${_LibraryScreenState.twoDigits(itemInfo!.$2)}E${_LibraryScreenState.twoDigits(itemInfo!.$1.number)}';
    final int percent = item.completed ? 100 : (item.fraction * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                PosterImage(asset: anime?.posterAsset ?? '', url: anime?.posterUrl, width: 34, height: 48, borderRadius: 8, fallbackLabel: anime?.title ?? '?'),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(anime?.title ?? item.animeId, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      if (episodeLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(episodeLabel, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                      ],
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (percent / 100).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: AppColors.divider,
                          valueColor: AlwaysStoppedAnimation<Color>(item.completed ? AppColors.primaryBright : AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$percent %', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
                    if (item.completed)
                      const Text('Terminé', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.primaryBright)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille (chip) réutilisée pour catégories et filtres — design AnimeBox.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon, required this.selected, required this.onTap, this.compact = false});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 13),
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
              icon,
              size: compact ? 14 : 15,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: compact ? 11.5 : 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
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
