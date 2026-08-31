import 'episode_quality.dart';
import 'video_quality.dart';

/// Un épisode d'une saison.
///
/// Les qualités disponibles seront, à terme, alimentées par le moteur de
/// synchronisation Telegram (plusieurs publications = plusieurs qualités
/// regroupées sur le même épisode).
class Episode {
  const Episode({
    required this.id,
    required this.number,
    this.title,
    required this.thumbnail,
    required this.date,
    this.isNew = false,
    required this.qualities,
    this.progress = Duration.zero,
  });

  final String id;
  final int number;
  final String? title;

  /// Vignette (image locale pour cette étape).
  final String thumbnail;

  /// Date de sortie (publication).
  final DateTime date;

  /// Badge « NOUVEAU ».
  final bool isNew;

  /// Qualités/langues disponibles pour ce même épisode.
  final List<EpisodeQuality> qualities;

  /// Progression de lecture locale — sera persistée côté serveur plus tard.
  final Duration progress;

  String get label => 'Épisode $number';

  /// Qualités triées de la meilleure à la moins bonne.
  List<EpisodeQuality> get sortedQualities => List.of(qualities)
    ..sort((EpisodeQuality a, EpisodeQuality b) {
      final int rank = a.quality.sortRank.compareTo(b.quality.sortRank);
      return rank != 0 ? rank : a.size.compareTo(b.size);
    });

  /// Meilleure qualité disponible.
  EpisodeQuality? get bestQuality => sortedQualities.isEmpty ? null : sortedQualities.first;

  EpisodeQuality? qualityOf(VideoQuality quality) {
    for (final EpisodeQuality option in qualities) {
      if (option.quality == quality) return option;
    }
    return null;
  }

  /// Qualités disponibles (filtre la disponibilité locale).
  List<EpisodeQuality> get availableQualities => qualities.where((EpisodeQuality q) => q.isAvailable).toList();

  /// Progression normalisée (0..1) pour les barres de progression.
  double? progressFraction(double episodeDurationMin) {
    if (progress <= Duration.zero) return null;
    final double total = Duration(minutes: episodeDurationMin.toInt()).inMilliseconds.toDouble();
    if (total <= 0) return null;
    return (progress.inMilliseconds / total).clamp(0.01, 1.0);
  }
}
