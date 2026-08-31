import 'package:flutter/foundation.dart';

import '../models/source_status.dart';
import '../models/sync_history_entry.dart';
import '../models/sync_progress.dart';
import '../models/sync_stats.dart';
import '../models/telegram_source.dart';

/// Contrat du service Telegram.
///
/// [MockTelegramService] l'implémente aujourd'hui avec des données locales ;
/// il sera remplacé par un vrai service (API Telegram + backend) sans
/// modifier les écrans, qui ne dépendent que de cette interface.
abstract class TelegramService implements Listenable {
  List<TelegramSource> get sources;

  TelegramSource? sourceById(String id);

  SyncStats get stats;

  bool get isSyncing;

  /// Progression de la synchronisation en cours (null si inactif).
  SyncProgress? get currentProgress;

  List<SyncHistoryEntry> get history;

  /// Ajoute une source à partir d'un nom d'utilisateur Telegram
  /// (validation locale du format faite par l'appelant si besoin).
  TelegramSource addSource({required String name, required String username});

  void removeSource(String sourceId);

  /// Active/désactive la synchronisation automatique d'une source.
  void setSourceEnabled(String sourceId, bool enabled);

  /// État d'erreur simulé possible (utilisé par les tests).
  SourceStatus? simulatedSourceStatus;

  /// Synchronise une source précise (ou toutes si [sourceId] est null).
  Future<void> syncSource({String? sourceId});

  /// Synchronise toutes les sources actives.
  Future<void> syncAll();
}
