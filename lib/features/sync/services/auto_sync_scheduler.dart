import '../models/sync_frequency.dart';

/// Planificateur de synchronisation automatique (règles 11 et 26).
///
/// Contrat minimal : appliquer une fréquence SOUHAITÉE, tout annuler.
/// L'implémentation de production ([WorkmanagerAutoSyncScheduler])
/// s'appuie sur WorkManager — le mécanisme Android adapté aux tâches
/// périodiques légères. AUCUNE boucle infinie, AUCUN service permanent
/// (règle 26) : le système réveille l'application quand il l'autorise.
abstract class AutoSyncScheduler {
  /// Prépare le moteur de planification (une fois, au démarrage).
  Future<void> initialize();

  /// Planifie (ou supprime, si [frequency] est `disabled`) la tâche
  /// périodique. Une même tâche unique est remplacée à chaque appel.
  Future<void> applyFrequency(SyncFrequency frequency);

  /// Annule toute synchronisation automatique planifiée.
  Future<void> cancel();
}
