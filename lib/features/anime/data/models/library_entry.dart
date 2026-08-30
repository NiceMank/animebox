import 'anime.dart';
import 'episode.dart';

/// Entrée de la bibliothèque personnelle de l'utilisateur.
class LibraryEntry {
  const LibraryEntry({
    required this.anime,
    this.isFavorite = false,
    this.lastWatched,
    this.progress = 0,
  });

  final Anime anime;
  final bool isFavorite;
  final Episode? lastWatched;

  /// Progression de visionnage du dernier épisode (0 à 1).
  final double progress;
}
