/// Statut d'une source Telegram.
enum SourceStatus { active, syncing, error, disabled }

extension SourceStatusX on SourceStatus {
  String get label => switch (this) {
        SourceStatus.active => 'Actif',
        SourceStatus.syncing => 'Synchronisation',
        SourceStatus.error => 'Erreur',
        SourceStatus.disabled => 'Désactivé',
      };
}
