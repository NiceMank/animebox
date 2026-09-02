/// Instantané de progression de lecture d'un épisode.
///
/// Structure prête à être sérialisée (JSON / base de données) lorsque le
/// backend sera disponible. Pour cette étape, elle est construite depuis
/// les données mockées du dépôt.
class PlaybackProgress {
  const PlaybackProgress({
    required this.animeId,
    required this.episodeId,
    required this.position,
    required this.duration,
    required this.savedAt,
    this.completed = false,
  });

  final String animeId;
  final String episodeId;
  final Duration position;
  final Duration duration;
  final DateTime savedAt;

  /// L'épisode a-t-il été regardé jusqu'au bout (donnée réelle) ?
  final bool completed;

  double get fraction {
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
  }
}
