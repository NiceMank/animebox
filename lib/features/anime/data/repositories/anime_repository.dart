import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../models/library_entry.dart';
import '../models/playback_progress.dart';
import '../models/playback_settings.dart';
import '../models/search_filters.dart';
import '../models/video_quality.dart';

/// Contrat d'accès aux données de l'application.
///
/// L'écran ne dépend que de cette interface : le dépôt mocké de l'étape 1
/// sera remplacé par un dépôt adossé à l'API backend (recherche serveur,
/// bibliothèque persistée…) sans modifier l'interface.
///
/// Les implémentations sont des [Listenable] : les écrans s'y abonnent pour
/// réagir aux changements (favoris, suivis, progression…).
abstract class AnimeRepository implements Listenable {
  List<Anime> get allAnime;

  Anime? byId(String id);

  /// Animé mis en avant sur l'accueil.
  Anime? get featured;

  /// Animés ayant au moins un épisode disponible (ordre : curation locale).
  List<Anime> get latestReleases;

  /// Ids des animés ayant reçu récemment un nouvel épisode (ordre récent).
  List<String> get recentEpisodeIds;

  /// Recherche locale : mots-clés (insensibles à la casse/aux accents)
  /// combinés aux filtres optionnels.
  List<Anime> search(String query, {SearchFilters filters = SearchFilters.empty});

  List<LibraryEntry> get libraryEntries;

  LibraryEntry? libraryEntryFor(String animeId);

  List<String> get availableGenres;
  List<String> get availableLanguages;
  List<String> get availableSources;
  List<int> get availableSeasons;

  // ---- Progression de lecture (locale pour cette étape) ----

  /// Progression enregistrée pour un épisode donné.
  Duration? episodeProgress(String animeId, String episodeId);

  /// Enregistre la progression réelle de lecture d'un épisode (prompt 8) :
  /// position, durée totale et statut terminé.
  ///
  /// La position est bornée à la durée de l'épisode et notifie les écrans.
  void recordProgress(
    String animeId,
    String episodeId,
    Duration position, {
    Duration duration = Duration.zero,
    bool completed = false,
  });

  /// L'épisode a-t-il déjà été terminé (reprise : redémarrer du début) ?
  bool episodeCompleted(String animeId, String episodeId) => false;

  /// Change la qualité préférée (persisté quand le dépôt le permet).
  void setPreferredQuality(QualityPreference preference);

  /// Historique de progression d'un animé (du plus récent au plus ancien).
  List<PlaybackProgress> progressHistory(String animeId);

  /// Paramètres de lecture courants.
  PlaybackSettings get playbackSettings;

  void setAutoPlayNext(bool enabled);

  // ---- Favoris / suivi ----

  void toggleFollow(String animeId);
  void toggleFavorite(String animeId);
}
