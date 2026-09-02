import 'package:workmanager/workmanager.dart';

import '../models/sync_frequency.dart';
import 'auto_sync_scheduler.dart';
import 'background_sync_runner.dart';

/// Nom unique de la tâche périodique AnimeBox.
const String kAutoSyncUniqueName = 'animebox.autoSync';

/// Nom de tâche reçu par le point d'entrée d'arrière-plan.
const String kAutoSyncTaskName = 'autoSync';

/// Point d'entrée de la tâche WorkManager — exécuté par Android dans un
/// isolat d'arrière-plan quand le SYSTÈME l'autorise (batterie, réseau,
/// maintenance Doze…). Jamais en permanence (règle 26).
@pragma('vm:entry-point')
void animeboxBackgroundCallbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, Object?>? inputData) async {
    if (task == kAutoSyncTaskName) {
      return runAnimeboxBackgroundSync();
    }
    return true;
  });
}

/// Planificateur RÉEL adossé à WorkManager — le mécanisme Android prévu
/// pour les tâches périodiques légères (règles 11/26) :
///
/// - intervalle minimal : 15 minutes (contrainte Android, respectée) ;
/// - réseau requis : la synchronisation n'a pas lieu sans connexion —
///   les données locales restent intactes (règle 23) ;
/// - différable : le système peut retarder l'exécution réelle (règle 12,
///   « fréquence souhaitée ») ;
/// - survit au redémarrage du téléphone sans réveil manuel.
class WorkmanagerAutoSyncScheduler implements AutoSyncScheduler {
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Workmanager().initialize(animeboxBackgroundCallbackDispatcher);
      _initialized = true;
    } catch (_) {
      // Greffon indisponible : la synchronisation manuelle reste possible.
    }
  }

  @override
  Future<void> applyFrequency(SyncFrequency frequency) async {
    await initialize();
    try {
      // Une seule tâche planifiée : annulée avant chaque replanification.
      await Workmanager().cancelByUniqueName(kAutoSyncUniqueName);
      final Duration? interval = frequency.interval;
      if (interval == null) return; // désactivée
      await Workmanager().registerPeriodicTask(
        kAutoSyncUniqueName,
        kAutoSyncTaskName,
        frequency: interval,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 10),
      );
    } catch (_) {
      // La planification a échoué : la synchronisation manuelle reste
      // disponible et l'application continue normalement.
    }
  }

  @override
  Future<void> cancel() async {
    await initialize();
    try {
      await Workmanager().cancelByUniqueName(kAutoSyncUniqueName);
    } catch (_) {}
  }
}
