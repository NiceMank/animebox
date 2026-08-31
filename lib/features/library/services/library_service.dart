import 'package:flutter/foundation.dart';

import '../../anime/data/models/anime.dart';
import '../../anime/data/models/library_entry.dart';
import '../../anime/data/repositories/anime_repository.dart';
import '../../telegram/data/services/episode_grouping_service.dart';

/// Regroupe les éléments de la bibliothèque en catégories.
///
/// Sépare la logique de présentation (tri, filtres) de l'interface ; sera
/// adossé au backend plus tard sans changer les écrans.
class LibraryService extends ChangeNotifier {
  LibraryService({required AnimeRepository repository, required EpisodeGroupingService groupingService}) {
    _repository = repository;
    _grouping = groupingService;
    _repository.addListener(notifyListeners);
    _grouping.addListener(notifyListeners);
  }

  late final AnimeRepository _repository;
  late final EpisodeGroupingService _grouping;

  @override
  void dispose() {
    _repository.removeListener(notifyListeners);
    _grouping.removeListener(notifyListeners);
    super.dispose();
  }

  List<LibraryEntry> get favorites =>
      [for (final LibraryEntry entry in _repository.libraryEntries) if (entry.isFavorite) entry];

  List<Anime> get followedAnime =>
      [for (final Anime anime in _repository.allAnime) if (anime.isFollowing) anime];

  /// Entrées avec une progression de lecture (section « Continuer »).
  List<LibraryEntry> get continueWatching =>
      [for (final LibraryEntry entry in _repository.libraryEntries) if (entry.hasProgress) entry];

  /// Derniers épisodes détectés par la synchronisation (mock).
  List<Anime> get recentlyAdded {
    final List<Anime> results = [
      for (final String id in _repository.recentEpisodeIds)
        if (_repository.byId(id) != null) _repository.byId(id)!,
    ];
    // Complété par les derniers épisodes du catalogue si besoin.
    if (results.isEmpty) {
      results.addAll(_repository.latestReleases.take(3));
    }
    return results;
  }

  List<Anime> get allAnime => _repository.allAnime;
}
