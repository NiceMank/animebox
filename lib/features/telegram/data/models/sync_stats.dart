/// Statistiques globales du moteur de synchronisation.
class SyncStats {
  const SyncStats({
    required this.analyzedPosts,
    required this.detectedAnime,
    required this.detectedEpisodes,
    required this.duplicatesGrouped,
    required this.newEpisodes,
    this.lastSync,
  });

  final int analyzedPosts;
  final int detectedAnime;
  final int detectedEpisodes;
  final int duplicatesGrouped;
  final int newEpisodes;
  final DateTime? lastSync;

  SyncStats copyWith({
    int? analyzedPosts,
    int? detectedAnime,
    int? detectedEpisodes,
    int? duplicatesGrouped,
    int? newEpisodes,
    DateTime? lastSync,
  }) =>
      SyncStats(
        analyzedPosts: analyzedPosts ?? this.analyzedPosts,
        detectedAnime: detectedAnime ?? this.detectedAnime,
        detectedEpisodes: detectedEpisodes ?? this.detectedEpisodes,
        duplicatesGrouped: duplicatesGrouped ?? this.duplicatesGrouped,
        newEpisodes: newEpisodes ?? this.newEpisodes,
        lastSync: lastSync ?? this.lastSync,
      );
}
