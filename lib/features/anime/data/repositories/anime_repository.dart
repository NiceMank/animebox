import 'package:flutter/foundation.dart';

import '../models/anime.dart';
import '../models/library_entry.dart';
import '../models/search_filters.dart';

/// Contrat d'accès aux données de l'application.
///
/// L'écran ne dépend que de cette interface : le dépôt mocké de l'étape 1
/// sera remplacé par un dépôt adossé à l'API backend (recherche serveur,
/// bibliothèque persistée…) sans modifier l'interface.
///
/// Les implémentations sont des [Listenable] : les écrans s'y abonnent pour
/// réagir aux changements (favoris, suivis…).
abstract class AnimeRepository implements Listenable {
  List<Anime> get allAnime;

  Anime? byId(String id);

  /// Animé mis en avant sur l'accueil.
  Anime? get featured;

  /// Animés ayant au moins un épisode disponible (ordre : curation locale).
  List<Anime> get latestReleases;

  /// Recherche locale : mots-clés (insensibles à la casse/aux accents)
  /// combinés aux filtres optionnels.
  List<Anime> search(String query, {SearchFilters filters = SearchFilters.empty});

  List<LibraryEntry> get libraryEntries;

  LibraryEntry? libraryEntryFor(String animeId);

  List<String> get availableGenres;
  List<String> get availableLanguages;
  List<String> get availableSources;
  List<int> get availableSeasons;

  void toggleFollow(String animeId);
  void toggleFavorite(String animeId);
}
