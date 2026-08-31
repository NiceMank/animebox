/// Une entrée de l'historique de synchronisation.
class SyncHistoryEntry {
  const SyncHistoryEntry({
    required this.id,
    required this.date,
    required this.success,
    required this.analyzedPosts,
    required this.newEpisodes,
    this.errorMessage,
  });

  final String id;
  final DateTime date;
  final bool success;
  final int analyzedPosts;
  final int newEpisodes;
  final String? errorMessage;

  String get summary {
    if (!success) return errorMessage ?? 'Erreur de synchronisation';
    final String episodes = newEpisodes == 1 ? '1 nouvel épisode' : '$newEpisodes nouveaux épisodes';
    return 'Synchronisation terminée — $episodes';
  }
}
