import 'package:flutter/foundation.dart';

import '../models/resolved_channel.dart';
import '../models/source_status.dart';
import '../models/sync_history_entry.dart';
import '../models/sync_progress.dart';
import '../models/sync_stats.dart';
import '../models/telegram_message.dart';
import '../models/telegram_source.dart';
import '../models/telegram_user.dart';

/// État de la connexion Telegram côté application.
enum TelegramAuthState { disconnected, connecting, connected, expired, error }

/// Contrat du service Telegram.
///
/// Deux implémentations :
/// - [MockTelegramService] : simulation locale (démo, développement) ;
/// - [ApiTelegramService] : vrai service, via le backend API (qui porte
///   les secrets Telegram côté serveur — jamais dans l'application).
///
/// Les écrans ne dépendent que de cette interface : remplacer
/// l'implémentation ne modifie aucune interface utilisateur.
abstract class TelegramService implements Listenable {
  /// `true` pour le service adossé au backend (informations d'interface).
  bool get isBackendApi;

  /// Adresse du backend utilisée (null en mode simulation).
  String? get apiBaseUrl;

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

  Future<TelegramSource> addSource({required String name, required String username});

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

  /// Recharge les statistiques et l'historique (mode backend).
  Future<void> loadStats();

  /// État d'erreur simulé possible (utilisé par les tests).
  SourceStatus? simulatedSourceStatus;

  /// Synchronise une source précise (ou toutes si [sourceId] est null).
  Future<void> syncSource({String? sourceId});

  /// Synchronise toutes les sources actives.
  Future<void> syncAll();
}
