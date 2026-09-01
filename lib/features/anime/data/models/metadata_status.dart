/// Statut d'enrichissement des métadonnées d'un animé (catalogue).
///
/// Miroir des statuts du backend (`app/metadata/service.py`) :
/// - `pending` : pas encore recherché ;
/// - `found` : associé avec confiance (fiche complète) ;
/// - `notFound` : rien de fiable → fiche minimale « Informations en attente » ;
/// - `reviewRequired` : correspondance incertaine → décision humaine ;
/// - `ignored` : correction manuelle (la revue est fermée).
enum MetadataStatus {
  pending('pending', 'En attente'),
  found('found', 'Enrichi'),
  notFound('not_found', 'Informations en attente'),
  reviewRequired('review_required', 'À vérifier'),
  ignored('ignored', 'Ignoré');

  const MetadataStatus(this.apiValue, this.label);

  /// Valeur brute renvoyée par l'API.
  final String apiValue;

  /// Libellé affichable.
  final String label;

  static MetadataStatus fromApi(Object? value) {
    final String raw = value?.toString() ?? '';
    for (final MetadataStatus status in MetadataStatus.values) {
      if (status.apiValue == raw) return status;
    }
    return MetadataStatus.pending;
  }

  /// La fiche doit-elle être présentée comme « à compléter » ?
  bool get isPendingInfo => this == MetadataStatus.pending || this == MetadataStatus.notFound;

  /// Une décision humaine est-elle attendue ?
  bool get needsReview => this == MetadataStatus.reviewRequired;
}
