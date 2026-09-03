import 'package:flutter/foundation.dart';

import '../../../notifications/models/notification_models.dart';
import '../gateway/telegram_gateway.dart';
import '../models/resolved_channel.dart';
import '../models/source_status.dart';
import '../models/sync_history_entry.dart';
import '../models/sync_progress.dart';
import '../models/sync_stats.dart';
import '../models/telegram_message.dart';
import '../models/telegram_source.dart';
import '../models/telegram_user.dart';

/// État de la connexion Telegram côté application.
///
/// Correspond aux états d'interface du prompt (connexion, code requis,
/// mot de passe 2FA requis, connecté, session expirée, erreur).
enum TelegramAuthState {
  disconnected,
  connecting,
  codeRequired,
  passwordRequired,
  connected,
  expired,
  error,
}

/// Contrat du service Telegram.
///
/// Deux implémentations (architecture 100 % LOCALE — aucun backend) :
/// - [LocalTelegramService] : client MTProto embarqué (TDLib) — l'utilisateur
///   s'authentifie avec SON compte ; la session chiffrée reste sur l'appareil ;
/// - [MockTelegramService] : simulation locale (démo, développement),
///   clairement signalée comme telle à l'écran.
///
/// Les écrans ne dépendent que de cette interface : remplacer
/// l'implémentation ne modifie aucune interface utilisateur.
abstract class TelegramService implements Listenable {
  /// Passerelle Telegram directe pour les médias (téléchargement/lecture
  /// via TDLib) — null quand le mode actif n'en dispose pas (démo).
  TelegramGateway? get mediaGateway => null;

  /// `true` quand le service dialogue RÉELLEMENT avec Telegram depuis
  /// l'appareil (client MTProto, TDLib). `false` pour le mock de démonstration.
  bool get isRealTelegram;

  // -------------------------------------------------------------------
  // Authentification
  // -------------------------------------------------------------------

  TelegramAuthState get authState;
  TelegramUser? get currentUser;

  /// Message d'erreur de connexion (état `error`), jamais de secret.
  String? get authError;

  /// Demande l'envoi du code de connexion Telegram.
  Future<void> requestCode(String phone);

  /// Vérifie le code reçu et ouvre la session.
  Future<void> verifyCode(String phone, String code);

  /// Vérifie le mot de passe 2FA (jamais contourné, jamais journalisé).
  Future<void> requestPassword(String password);

  Future<void> disconnect();

  /// Revalide la session (état `expired` si le jeton est révoqué).
  Future<void> refreshSession();

  // -------------------------------------------------------------------
  // Sources
  // -------------------------------------------------------------------

  List<TelegramSource> get sources;

  /// Recharge les sources depuis le backend (no-op en mode simulé).
  Future<void> loadSources();

  TelegramSource? sourceById(String id);

  /// Résout un canal via le backend (aperçu avant ajout).
  Future<ResolvedChannel> resolveChannel(String input);

  Future<TelegramSource> addSource({
    required String name,
    required String username,
    String? channelId,
    String kind = 'channel',
    String? inviteHash,
  });

  Future<void> removeSource(String sourceId);

  /// Active/désactive la synchronisation automatique d'une source.
  Future<void> setSourceEnabled(String sourceId, bool enabled);

  // -------------------------------------------------------------------
  // Publications (récupération de test — analyse intelligente plus tard)
  // -------------------------------------------------------------------

  Future<List<TelegramMessage>> fetchMessages(String sourceId, {int limit = 20});

  // -------------------------------------------------------------------
  // Synchronisation
  // -------------------------------------------------------------------

  SyncStats get stats;
  bool get isSyncing;
  SyncProgress? get currentProgress;
  List<SyncHistoryEntry> get history;

  /// Résumé de la DERNIÈRE synchronisation RÉELLE (prompt 9 — règle 21) :
  /// valeurs mesurées pendant la passe, jamais simulées. Null tant
  /// qu'aucune synchronisation n'a abouti dans cette session.
  SyncRunSummary? get lastSyncSummary;

  /// Callback branché par l'application (centre de notifications) :
  /// appelé après chaque passe de synchronisation réelle, y compris
  /// en cas de réussite partielle. Aucun appel = aucune notification
  /// (jamais de fausse notification — règle 32).
  void Function(SyncRunSummary summary)? onSyncCompleted;

  /// Recharge les statistiques et l'historique (mode backend).
  Future<void> loadStats();

  /// État d'erreur simulé possible (utilisé par les tests).
  SourceStatus? simulatedSourceStatus;

  /// Synchronise une source précise (ou toutes si [sourceId] est null).
  Future<void> syncSource({String? sourceId});

  /// Synchronise toutes les sources actives.
  Future<void> syncAll();

  /// Demande l'arrêt propre de la synchronisation en cours.
  Future<void> cancelSync();
}
