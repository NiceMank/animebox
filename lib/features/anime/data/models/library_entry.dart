import 'anime.dart';
import 'episode.dart';

/// Entrée de la bibliothèque personnelle de l'utilisateur.
class LibraryEntry {
  const LibraryEntry({
    required this.anime,
    this.isFavorite = false,
    this.progressMap = const {},
    this.resumeEpisodeId,
  });

  final Anime anime;
  final bool isFavorite;

  /// Progression de lecture par épisode (id d'épisode → position).
  ///
  /// Séparée de l'interface : elle sera persistée en base de données
  /// (et synchronisée) dans une étape ultérieure.
  final Map<String, Duration> progressMap;

  /// Dernier épisode regardé (utilisé pour « Reprendre »).
  final String? resumeEpisodeId;

  Duration? progressFor(String episodeId) => progressMap[episodeId];

  Episode? get resumeEpisode {
    if (resumeEpisodeId == null) return null;
    return anime.episodeById(resumeEpisodeId!);
  }

  Duration? get resumePosition {
    final Episode? episode = resumeEpisode;
    return episode == null ? null : progressFor(episode.id);
  }

  bool get hasProgress => progressMap.values.any((Duration position) => position > Duration.zero);

  /// Fraction 0..1 de l'épisode repris (pour les barres de progression).
  double? resumeFraction() {
    final Episode? episode = resumeEpisode;
    final Duration? position = resumePosition;
    if (episode == null || position == null || position <= Duration.zero) return null;
    final double total = Duration(minutes: anime.episodeDurationMin.toInt()).inMilliseconds.toDouble();
    if (total <= 0) return null;
    return (position.inMilliseconds / total).clamp(0.01, 1.0);
  }

  /// Nombre d'épisodes commencés.
  int get startedCount => progressMap.values.where((Duration position) => position > Duration.zero).length;

  LibraryEntry copyWith({bool? isFavorite, Map<String, Duration>? progressMap, String? resumeEpisodeId}) => LibraryEntry(
        anime: anime,
        isFavorite: isFavorite ?? this.isFavorite,
        progressMap: progressMap ?? this.progressMap,
        resumeEpisodeId: resumeEpisodeId ?? this.resumeEpisodeId,
      );
}
