/// Progression d'une synchronisation en cours.
class SyncProgress {
  const SyncProgress({
    this.fraction,
    required this.phase,
    required this.analyzedPosts,
    required this.totalPosts,
  });

  /// Avancement de 0 à 1 — null quand la progression est indéterminée
  /// (requête backend en cours, sans jauge détaillée).
  final double? fraction;

  /// Phase actuelle (« Analyzing publications... », …).
  final String phase;

  /// Publications analysées jusqu'ici.
  final int analyzedPosts;

  /// Total attendu pour cette passe.
  final int totalPosts;

  int? get percent => fraction == null ? null : (fraction! * 100).round();

  SyncProgress copyWith({double? fraction, String? phase, int? analyzedPosts, int? totalPosts}) =>
      SyncProgress(
        fraction: fraction ?? this.fraction,
        phase: phase ?? this.phase,
        analyzedPosts: analyzedPosts ?? this.analyzedPosts,
        totalPosts: totalPosts ?? this.totalPosts,
      );
}
