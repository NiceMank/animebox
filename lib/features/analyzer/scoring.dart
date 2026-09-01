/// Score de confiance et niveaux de fiabilité — port fidèle de
/// `backend/app/analyzer/scoring.py`.
library;

import 'models.dart';

const int levelHigh = 85;
const int levelMedium = 65;
const int levelLow = 40;

/// Calcule (confiance, statut) pour une analyse.
(int, String) scoreAnalysis(AnalysisResult result) {
  int points = 0;

  // Titre
  if (result.titleMatched && result.animeKey != null) {
    points += result.titleViaAlias ? 26 : 33;
  } else if (result.titleKey != null) {
    points += 14;
  }

  // Saison
  if (result.season != null) points += 15;

  // Épisode
  if (result.episodeSource == 'combined' || result.episodeSource == 'standalone') {
    points += 22;
  } else if (result.episodeSource == 'heuristic_known') {
    points += 18;
  } else if (result.episodeSource == 'heuristic') {
    points += 10;
  } else if (result.episodeKind == 'special') {
    points += 8;
  }

  // Qualité
  if (result.qualitySource == 'explicit') {
    points += 15;
  } else if (result.qualitySource == 'metadata') {
    points += 10;
  }

  // Langue
  if (result.language != 'unknown') points += 10;

  // Sous-titres
  if (result.subtitles != null) points += 5;

  // Année cohérente avec l'année de sortie connue du catalogue
  if (result.year != null && result.releaseYear != null && result.year == result.releaseYear) {
    points += 5;
  }

  // Format combiné S02E08 / 2x08 : très fiable
  if (result.seasonSource == 'combined' && result.episodeSource == 'combined') {
    points += 3;
  }

  // Contradictions détectées : pénalité
  points -= 10 * result.warnings.length;
  points = points.clamp(0, 99);

  final String status;
  if (result.titleKey == null) {
    status = kStatusNeedsReview;
  } else if (points >= levelHigh) {
    status = kStatusHigh;
  } else if (points >= levelMedium) {
    status = kStatusMedium;
  } else if (points >= levelLow) {
    status = kStatusLow;
  } else {
    status = kStatusNeedsReview;
  }
  return (points, status);
}
