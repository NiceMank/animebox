import 'package:flutter/widgets.dart';

import '../../local/data/local_database.dart';
import '../../notifications/models/notification_models.dart';
import '../../notifications/services/local_notification_service.dart';
import '../../notifications/services/notification_center.dart';
import '../../notifications/services/notification_settings.dart';
import '../../telegram/data/gateway/tdlib_gateway.dart';
import '../../telegram/data/gateway/telegram_gateway.dart';
import '../../telegram/data/services/local_sync_service.dart';
import '../../telegram/data/services/telegram_session_manager.dart';

/// Exécution RÉELLE d'une synchronisation en tâche de fond (règles 11
/// à 16).
///
/// Contraintes respectées :
/// - LÉGÈRE : synchronisation incrémentale (curseur par source), jamais
///   de téléchargement de vidéo (règles 14/15) ;
/// - LIMITÉE : seules les sources ACTIVÉES sont synchronisées (règle 16) ;
/// - ÉCONOME : la tâche se termine dès que possible, sans connexion
///   persistante (règle 14) ;
/// - HONNÊTE : en cas d'échec (session expirée, pas de réseau), aucune
///   fausse notification n'est produite — la prochaine exécution
///   système réessaiera (règles 23/24/32).
///
/// Renvoie `true` quand la tâche s'est terminée (WorkManager ne doit
/// pas réessayer immédiatement : la prochaine période planifiée suffit —
/// aucune tempête de réessais).
Future<bool> runAnimeboxBackgroundSync() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Identifiants de compilation (jamais dans le dépôt, les journaux ou
  // les écrans). Sans eux, l'application est en mode démo : rien à faire.
  const String rawId = String.fromEnvironment('ANIMEBOX_TELEGRAM_API_ID');
  const String apiHash = String.fromEnvironment('ANIMEBOX_TELEGRAM_API_HASH');
  final int apiId = int.tryParse(rawId) ?? 0;
  if (apiId <= 0 || apiHash.isEmpty) return true;

  LocalDatabase? database;
  TelegramGateway? gateway;
  try {
    database = await LocalDatabase.open();
    if (database == null) return true;

    // Aucune source activée → aucune réveil inutile du réseau (règle 16).
    final List<Map<String, Object?>> targets = [
      for (final Map<String, Object?> row in await database.listSources())
        if (((row['sync_enabled'] as num?)?.toInt() ?? 1) != 0) row,
    ];
    if (targets.isEmpty) return true;

    // Session enregistrée ? Sinon, inutile d'insister (règle 24) : la
    // reconnexion est une action utilisateur, pas une tâche de fond.
    final TelegramSessionManager sessions =
        TelegramSessionManager(store: PlatformSecureStore());
    if (!await sessions.wasConnected()) return true;

    final TdlibTelegramGateway tdlib = TdlibTelegramGateway(
      apiId: apiId,
      apiHash: apiHash,
    );
    gateway = tdlib;
    try {
      tdlib.setEncryptionKey(await sessions.ensureEncryptionKey());
    } catch (_) {
      // Sans stockage sécurisé, TDLib gère son propre chiffrement.
    }
    await tdlib.connect();

    // Attente bornée de l'état « connecté » (TDLib restaure la session
    // de façon asynchrone). Jamais de boucle infinie (règle 26) : au
    // plus 20 secondes, puis abandon propre.
    final Stopwatch watch = Stopwatch()..start();
    while (tdlib.authState != GatewayAuthState.connected &&
        watch.elapsed < const Duration(seconds: 20)) {
      if (tdlib.authState == GatewayAuthState.sessionExpired ||
          tdlib.authState == GatewayAuthState.error) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (tdlib.authState != GatewayAuthState.connected) return true;

    // Synchronisation incrémentale légère : petites pages uniquement —
    // le curseur par source fait le reste (règle 14).
    final LocalSyncService sync = LocalSyncService(
      gateway: tdlib,
      database: database,
      pageSize: 20,
    );

    final NotificationSettings settings = NotificationSettings(database: database);
    await settings.load();
    final LocalNotificationService notifications = LocalNotificationService();
    await notifications.initialize();
    final NotificationCenter center = NotificationCenter(
      notifications: notifications,
      settings: settings,
      database: database,
    );

    int analyzed = 0;
    int episodes = 0;
    int qualities = 0;
    int done = 0;
    int errors = 0;
    final List<SyncRunEpisode> updates = <SyncRunEpisode>[];
    for (final Map<String, Object?> row in targets) {
      final LocalSyncResult result = await sync.syncSource(row);
      if (result.errorMessage != null) {
        errors += 1;
        continue;
      }
      done += 1;
      analyzed += result.analyzed;
      episodes += result.newEpisodes;
      qualities += result.grouped;
      updates.addAll(result.episodeUpdates);
    }

    if (done > 0) {
      await center.handleSyncSummary(SyncRunSummary(
        finishedAt: DateTime.now(),
        sourcesAnalyzed: done,
        newMessages: analyzed,
        newEpisodes: episodes,
        newQualities: qualities,
        errors: errors,
        episodes: updates,
      ));
    }
    return true;
  } catch (_) {
    // Une tâche de fond ne replante jamais le système : échec silencieux,
    // la prochaine période planifiée réessaiera.
    return true;
  } finally {
    if (gateway != null) {
      try {
        await gateway.close();
      } catch (_) {}
    }
    if (database != null) {
      try {
        await database.close();
      } catch (_) {}
    }
  }
}
