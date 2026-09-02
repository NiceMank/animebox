// Paramètres publics simples : la forme abrégée (identifiant privé en
// argument nommé) est impossible — voir NotificationCenter.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../local/data/local_database.dart';
import '../../sync/models/sync_frequency.dart';
import '../../sync/services/auto_sync_scheduler.dart';

/// Réglages de notifications et de synchronisation (prompt 9).
///
/// Tout est persisté localement (table `settings`, colonnes dédiées des
/// tables `sources` et `anime`) — aucune préférence ne quitte l'appareil.
///
/// - notifications nouveaux épisodes (règle 4) ;
/// - notifications de téléchargement et progression (règles 8 à 10) ;
/// - mode silencieux (règle 19) et heures silencieuses (règle 20) ;
/// - fréquence souhaitée de synchronisation automatique (règle 12),
///   appliquée via [AutoSyncScheduler] ;
/// - préférences PAR SOURCE (règle 17) et PAR ANIMÉ (règle 18).
class NotificationSettings extends ChangeNotifier {
  NotificationSettings({LocalDatabase? database, DateTime Function()? now})
      : _database = database,
        _now = now ?? DateTime.now;

  static const String _keyNewEpisodes = 'notif_new_episodes';
  static const String _keyDownloads = 'notif_downloads';
  static const String _keyProgress = 'notif_download_progress';
  static const String _keySilent = 'notif_silent_mode';
  static const String _keyQuietEnabled = 'notif_quiet_enabled';
  static const String _keyQuietStart = 'notif_quiet_start';
  static const String _keyQuietEnd = 'notif_quiet_end';
  static const String _keyFrequency = 'auto_sync_frequency';

  final LocalDatabase? _database;
  final DateTime Function() _now;

  bool _newEpisodes = true;
  bool _downloads = true;
  bool _progress = true;
  bool _silent = false;
  bool _quietEnabled = false;
  int _quietStart = 23 * 60; // 23:00
  int _quietEnd = 7 * 60; // 07:00
  SyncFrequency _frequency = SyncFrequency.disabled;
  bool _loaded = false;

  AutoSyncScheduler? _scheduler;

  // -------------------------------------------------------------------
  // Lecture des valeurs
  // -------------------------------------------------------------------

  bool get newEpisodesEnabled => _newEpisodes;
  bool get downloadNotificationsEnabled => _downloads;
  bool get downloadProgressEnabled => _progress;
  bool get silentMode => _silent;
  bool get quietHoursEnabled => _quietEnabled;
  int get quietStartMinutes => _quietStart;
  int get quietEndMinutes => _quietEnd;
  SyncFrequency get syncFrequency => _frequency;
  bool get loaded => _loaded;

  /// Branche le planificateur (appelé au démarrage de l'application).
  void attachScheduler(AutoSyncScheduler scheduler) => _scheduler = scheduler;

  /// Charge les préférences persistées (une fois, au démarrage).
  Future<void> load() async {
    final LocalDatabase? db = _database;
    if (db == null) {
      _loaded = true;
      return;
    }
    try {
      _newEpisodes = (await db.getSetting(_keyNewEpisodes)) != '0';
      _downloads = (await db.getSetting(_keyDownloads)) != '0';
      _progress = (await db.getSetting(_keyProgress)) != '0';
      _silent = (await db.getSetting(_keySilent)) == '1';
      _quietEnabled = (await db.getSetting(_keyQuietEnabled)) == '1';
      _quietStart = int.tryParse(await db.getSetting(_keyQuietStart) ?? '') ?? _quietStart;
      _quietEnd = int.tryParse(await db.getSetting(_keyQuietEnd) ?? '') ?? _quietEnd;
      _frequency = SyncFrequency.fromId(await db.getSetting(_keyFrequency));
    } catch (_) {
      // Base indisponible : valeurs par défaut raisonnables.
    }
    _loaded = true;
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Modifications (persistées, interface notifiée)
  // -------------------------------------------------------------------

  Future<void> setNewEpisodesEnabled(bool value) => _update(_keyNewEpisodes, value, (bool v) => _newEpisodes = v);

  Future<void> setDownloadNotificationsEnabled(bool value) => _update(_keyDownloads, value, (bool v) => _downloads = v);

  Future<void> setDownloadProgressEnabled(bool value) => _update(_keyProgress, value, (bool v) => _progress = v);

  Future<void> setSilentMode(bool value) => _update(_keySilent, value, (bool v) => _silent = v);

  Future<void> setQuietHoursEnabled(bool value) => _update(_keyQuietEnabled, value, (bool v) => _quietEnabled = v);

  Future<void> setQuietHours({required int startMinutes, required int endMinutes}) async {
    _quietStart = startMinutes.clamp(0, 1439);
    _quietEnd = endMinutes.clamp(0, 1439);
    await _persist(_keyQuietStart, '$_quietStart');
    await _persist(_keyQuietEnd, '$_quietEnd');
    notifyListeners();
  }

  /// Change la fréquence souhaitée : persistée puis appliquée au
  /// planificateur réel (règle 12 — présentée comme une fréquence
  /// souhaitée, jamais garantie).
  Future<void> setSyncFrequency(SyncFrequency frequency) async {
    _frequency = frequency;
    await _persist(_keyFrequency, frequency.id);
    try {
      await _scheduler?.applyFrequency(frequency);
    } catch (_) {
      // Planificateur indisponible : la préférence est conservée et la
      // synchronisation manuelle reste disponible.
    }
    notifyListeners();
  }

  Future<void> _update(String key, bool value, void Function(bool) apply) async {
    apply(value);
    await _persist(key, value ? '1' : '0');
    notifyListeners();
  }

  Future<void> _persist(String key, String value) async {
    try {
      await _database?.setSetting(key, value);
    } catch (_) {}
  }

  // -------------------------------------------------------------------
  // Préférences PAR SOURCE (règle 17)
  // -------------------------------------------------------------------

  /// La source accepte-t-elle les notifications ? (défaut : oui — la
  /// désactivation est un choix explicite, conservé indéfiniment.)
  Future<bool> isSourceNotificationsEnabled(String sourceId) async {
    final LocalDatabase? db = _database;
    if (db == null) return true;
    try {
      final Map<String, Object?>? row = await db.getSource(sourceId);
      if (row == null) return true;
      return ((row['notifications_enabled'] as num?)?.toInt() ?? 1) != 0;
    } catch (_) {
      return true;
    }
  }

  Future<void> setSourceNotificationsEnabled(String sourceId, bool enabled) async {
    final LocalDatabase? db = _database;
    if (db == null) return;
    try {
      final Map<String, Object?>? row = await db.getSource(sourceId);
      if (row == null) return;
      await db.upsertSource(Map<String, Object?>.from(row)
        ..['notifications_enabled'] = enabled ? 1 : 0);
    } catch (_) {}
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Préférences PAR ANIMÉ (règle 18) — sans retirer l'animé du catalogue
  // -------------------------------------------------------------------

  Future<bool> isAnimeNotificationsEnabled(String animeId) async {
    final LocalDatabase? db = _database;
    if (db == null) return true;
    try {
      final Map<String, Object?>? row = await db.getAnime(animeId);
      if (row == null) return true;
      return ((row['notifications_enabled'] as num?)?.toInt() ?? 1) != 0;
    } catch (_) {
      return true;
    }
  }

  Future<void> setAnimeNotificationsEnabled(String animeId, bool enabled) async {
    final LocalDatabase? db = _database;
    if (db == null) return;
    try {
      final Map<String, Object?>? row = await db.getAnime(animeId);
      if (row == null) return;
      await db.upsertAnime(Map<String, Object?>.from(row)
        ..['notifications_enabled'] = enabled ? 1 : 0);
    } catch (_) {}
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Heures silencieuses (règle 20)
  // -------------------------------------------------------------------

  /// `true` si l'instant [time] (défaut : maintenant) tombe dans la plage
  /// silencieuse. Gère les plages qui enjambent minuit (23:00 → 07:00).
  bool isInQuietHours([DateTime? time]) {
    if (!_quietEnabled || _quietStart == _quietEnd) return false;
    final DateTime t = time ?? _now();
    final int minute = t.hour * 60 + t.minute;
    if (_quietStart < _quietEnd) {
      return minute >= _quietStart && minute < _quietEnd;
    }
    return minute >= _quietStart || minute < _quietEnd;
  }

  /// L'alerte doit-elle être discrète ? Mode silencieux global OU
  /// heures silencieuses en cours (règles 19/20 — sans contourner les
  /// réglages système, le canal Android choisi est simplement discret).
  bool shouldDeliverSilently([DateTime? time]) => _silent || isInQuietHours(time);
}
