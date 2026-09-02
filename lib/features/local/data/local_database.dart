import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'db_factory.dart';

/// Base de données LOCALE d'AnimeBox (aucun serveur).
///
/// Contient : sources Telegram, catalogue (animés, saisons, épisodes,
/// versions), favoris, progression, historique et statuts de synchronisation.
/// Aucune donnée n'est envoyée hors de l'appareil.
class LocalDatabase {
  LocalDatabase._(this._db);

  final Database _db;

  static const String _fileName = 'animebox_local.db';

  /// Ouvre (ou crée) la base locale. En cas d'échec, renvoie null —
  /// l'appelant bascule alors en mode mémoire (jamais de plantage).
  static Future<LocalDatabase?> open({String? directoryPath}) async {
    try {
      final DatabaseFactory? factory = await resolveDatabaseFactory();
      if (factory == null) return null;
      final String path = p.join(
        directoryPath ?? await factory.getDatabasesPath(),
        _fileName,
      );
      final Database db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: _createSchema,
          onUpgrade: _upgradeSchema,
        ),
      );
      return LocalDatabase._(db);
    } catch (_) {
      return null;
    }
  }

  /// Base EN MÉMOIRE (tests) : même schéma, aucune persistance disque.
  static Future<LocalDatabase?> openInMemory() async {
    try {
      final DatabaseFactory? factory = await resolveDatabaseFactory();
      if (factory == null) return null;
      final Database db = await factory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: _createSchema,
          onUpgrade: _upgradeSchema,
        ),
      );
      return LocalDatabase._(db);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        username TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'channel',
        photo_url TEXT,
        description TEXT,
        invite_hash TEXT,
        chat_id INTEGER,
        status TEXT NOT NULL DEFAULT 'active',
        last_sync TEXT,
        last_message_id INTEGER,
        analyzed_posts INTEGER NOT NULL DEFAULT 0,
        detected_anime INTEGER NOT NULL DEFAULT 0,
        detected_episodes INTEGER NOT NULL DEFAULT 0,
        sync_enabled INTEGER NOT NULL DEFAULT 1,
        notifications_enabled INTEGER NOT NULL DEFAULT 1,
        auto_download INTEGER NOT NULL DEFAULT 0,
        preferred_quality TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE anime (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        canonical_title TEXT,
        original_title TEXT,
        poster_asset TEXT,
        backdrop_asset TEXT,
        description TEXT,
        genres TEXT NOT NULL DEFAULT '[]',
        year INTEGER,
        source TEXT,
        created_at TEXT NOT NULL,
        notifications_enabled INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE season (
        id TEXT PRIMARY KEY,
        anime_id TEXT NOT NULL,
        number INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE episode (
        id TEXT PRIMARY KEY,
        season_id TEXT NOT NULL,
        number INTEGER NOT NULL,
        kind TEXT NOT NULL DEFAULT 'regular',
        title TEXT,
        date TEXT,
        is_new INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE version (
        id TEXT PRIMARY KEY,
        episode_id TEXT NOT NULL,
        quality TEXT,
        quality_rank INTEGER NOT NULL DEFAULT 0,
        language TEXT,
        subtitles TEXT,
        resolution TEXT,
        size INTEGER,
        media_type TEXT,
        file_name TEXT,
        duration INTEGER,
        width INTEGER,
        height INTEGER,
        file_id INTEGER,
        telegram_channel_id TEXT,
        telegram_channel_username TEXT,
        telegram_message_id INTEGER,
        telegram_message_link TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE favorites (
        anime_id TEXT PRIMARY KEY
      )
    ''');
    await db.execute('''
      CREATE TABLE progress (
        anime_id TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        completed INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (anime_id, episode_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE downloads (
        id TEXT PRIMARY KEY,
        version_id TEXT NOT NULL UNIQUE,
        anime_id TEXT NOT NULL,
        season_id TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        chat_id INTEGER,
        message_id INTEGER,
        file_id INTEGER,
        quality TEXT,
        language TEXT,
        anime_title TEXT,
        season_number INTEGER,
        episode_number INTEGER,
        message_link TEXT,
        channel_username TEXT,
        status TEXT NOT NULL,
        total_bytes INTEGER,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        local_path TEXT,
        file_name TEXT,
        error TEXT,
        resumable INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id TEXT,
        date TEXT NOT NULL,
        success INTEGER NOT NULL,
        analyzed_posts INTEGER NOT NULL DEFAULT 0,
        new_episodes INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE notified_episodes (
        episode_id TEXT PRIMARY KEY,
        anime_id TEXT NOT NULL,
        anime_title TEXT,
        season_number INTEGER NOT NULL DEFAULT 1,
        episode_number INTEGER NOT NULL DEFAULT 0,
        quality_count INTEGER NOT NULL DEFAULT 1,
        notified_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_season_anime ON season(anime_id)');
    await db.execute('CREATE INDEX idx_episode_season ON episode(season_id)');
    await db.execute('CREATE INDEX idx_version_episode ON version(episode_id)');
    await db.execute('CREATE INDEX idx_version_message ON version(telegram_message_id)');
  await db.execute('CREATE INDEX idx_downloads_status ON downloads(status)');
  }

  /// Migration v1 → v2 : téléchargements, file_id des versions, progression
  /// enrichie (durée + statut terminé). Aucune perte de données.
  static Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfExists(db, 'version', 'file_id', 'INTEGER');
      await _addColumnIfExists(db, 'progress', 'duration_ms', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfExists(db, 'progress', 'completed', 'INTEGER NOT NULL DEFAULT 0');
      await db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS downloads (
          id TEXT PRIMARY KEY,
          version_id TEXT NOT NULL UNIQUE,
          anime_id TEXT NOT NULL,
          season_id TEXT NOT NULL,
          episode_id TEXT NOT NULL,
          chat_id INTEGER,
          message_id INTEGER,
          file_id INTEGER,
          quality TEXT,
          language TEXT,
          anime_title TEXT,
          season_number INTEGER,
          episode_number INTEGER,
          message_link TEXT,
          status TEXT NOT NULL,
          total_bytes INTEGER,
          downloaded_bytes INTEGER NOT NULL DEFAULT 0,
          local_path TEXT,
          file_name TEXT,
          error TEXT,
          resumable INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_downloads_status ON downloads(status)');
    }
    if (oldVersion < 3) {
      // Colonnes de téléchargements présentes dans le gestionnaire mais
      // absentes du schéma initial (réparées — lien et canal réels).
      await _addColumnIfExists(db, 'downloads', 'message_link', 'TEXT');
      await _addColumnIfExists(db, 'downloads', 'channel_username', 'TEXT');
      // Prompt 9 : préférences de notifications (par source, par animé) et
      // registre des épisodes déjà notifiés. Paramètres par source
      // préparés (téléchargement automatique OFF, qualité héritée).
      await _addColumnIfExists(db, 'sources', 'notifications_enabled', 'INTEGER NOT NULL DEFAULT 1');
      await _addColumnIfExists(db, 'sources', 'auto_download', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfExists(db, 'sources', 'preferred_quality', 'TEXT');
      await _addColumnIfExists(db, 'anime', 'notifications_enabled', 'INTEGER NOT NULL DEFAULT 1');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notified_episodes (
          episode_id TEXT PRIMARY KEY,
          anime_id TEXT NOT NULL,
          anime_title TEXT,
          season_number INTEGER NOT NULL DEFAULT 1,
          episode_number INTEGER NOT NULL DEFAULT 0,
          quality_count INTEGER NOT NULL DEFAULT 1,
          notified_at TEXT NOT NULL
        )
      ''');
    }
  }

  static Future<void> _addColumnIfExists(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final List<Map<String, Object?>> columns = await db.rawQuery('PRAGMA table_info($table)');
    final bool exists = columns.any((Map<String, Object?> c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> close() => _db.close();

  // ---------------------------------------------------------------------
  // Sources
  // ---------------------------------------------------------------------

  Future<void> upsertSource(Map<String, Object?> source) async {
    await _db.insert('sources', source, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> listSources() async {
    return _db.query('sources', orderBy: 'name');
  }

  Future<Map<String, Object?>?> getSource(String id) async {
    final List<Map<String, Object?>> rows = await _db.query('sources', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> deleteSource(String id) async {
    await _db.delete('sources', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // Catalogue (anime → saisons → épisodes → versions)
  // ---------------------------------------------------------------------

  Future<void> upsertAnime(Map<String, Object?> anime) async {
    await _db.insert('anime', anime, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertSeason(Map<String, Object?> season) async {
    await _db.insert('season', season, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertEpisode(Map<String, Object?> episode) async {
    await _db.insert('episode', episode, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertVersion(Map<String, Object?> version) async {
    await _db.insert('version', version, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Insère un graphe complet de manière transactionnelle.
  Future<void> saveCatalogGraph({
    required List<Map<String, Object?>> anime,
    required List<Map<String, Object?>> seasons,
    required List<Map<String, Object?>> episodes,
    required List<Map<String, Object?>> versions,
  }) async {
    await _db.transaction((Transaction txn) async {
      for (final Map<String, Object?> a in anime) {
        await txn.insert('anime', a, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final Map<String, Object?> s in seasons) {
        await txn.insert('season', s, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final Map<String, Object?> e in episodes) {
        await txn.insert('episode', e, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final Map<String, Object?> v in versions) {
        await txn.insert('version', v, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, Object?>>> listAnime() => _db.query('anime', orderBy: 'title');

  Future<Map<String, Object?>?> getAnime(String animeId) async {
    final List<Map<String, Object?>> rows = await _db.query('anime', where: 'id = ?', whereArgs: [animeId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> getSeason(String seasonId) async {
    final List<Map<String, Object?>> rows = await _db.query('season', where: 'id = ?', whereArgs: [seasonId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> getEpisode(String episodeId) async {
    final List<Map<String, Object?>> rows = await _db.query('episode', where: 'id = ?', whereArgs: [episodeId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> hasEpisode(String episodeId) async => (await getEpisode(episodeId)) != null;

  Future<Map<String, Object?>?> getSeasonByNumber(String animeId, int number) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'season',
      where: 'anime_id = ? AND number = ?',
      whereArgs: [animeId, number],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> getEpisodeByNumber(String seasonId, int number) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'episode',
      where: 'season_id = ? AND number = ?',
      whereArgs: [seasonId, number],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> listSeasons(String animeId) =>
      _db.query('season', where: 'anime_id = ?', whereArgs: [animeId], orderBy: 'number');

  Future<List<Map<String, Object?>>> listEpisodes(String seasonId) =>
      _db.query('episode', where: 'season_id = ?', whereArgs: [seasonId], orderBy: 'number');

  Future<List<Map<String, Object?>>> listVersions(String episodeId) =>
      _db.query('version', where: 'episode_id = ?', whereArgs: [episodeId], orderBy: 'quality_rank DESC');

  /// Charge tout le catalogue en une seule passe (graphe complet).
  Future<Map<String, Object?>> loadCatalog() async {
    final Map<String, Object?> result = {};
    result['anime'] = await _db.query('anime', orderBy: 'title');
    result['seasons'] = await _db.query('season');
    result['episodes'] = await _db.query('episode');
    result['versions'] = await _db.query('version');
    return result;
  }

  /// Comptage rapide pour décider du seed initial.
  Future<int> countAnime() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM anime');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<bool> hasVersionForMessage(int messageId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'version',
      columns: ['id'],
      where: 'telegram_message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // ---------------------------------------------------------------------
  // Favoris / progression / historique
  // ---------------------------------------------------------------------

  Future<Set<String>> loadFavorites() async {
    final List<Map<String, Object?>> rows = await _db.query('favorites');
    return rows.map((Map<String, Object?> r) => r['anime_id']! as String).toSet();
  }

  Future<void> setFavorite(String animeId, bool favorite) async {
    if (favorite) {
      await _db.insert('favorites', {'anime_id': animeId}, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await _db.delete('favorites', where: 'anime_id = ?', whereArgs: [animeId]);
    }
  }

  /// Position seule (compatibilité) — voir [loadProgressDetails].
  Future<Map<String, int>> loadProgress() async {
    final List<Map<String, Object?>> rows = await _db.query('progress');
    return {
      for (final Map<String, Object?> r in rows)
        '${r['anime_id']}|${r['episode_id']}': (r['position_ms'] as num?)?.toInt() ?? 0,
    };
  }

  /// Progression complète : position, durée, statut terminé (prompt 8).
  /// Clé : `animeId|episodeId`.
  Future<Map<String, Map<String, Object?>>> loadProgressDetails() async {
    final List<Map<String, Object?>> rows = await _db.query('progress');
    return {
      for (final Map<String, Object?> r in rows)
        '${r['anime_id']}|${r['episode_id']}': {
          'positionMs': (r['position_ms'] as num?)?.toInt() ?? 0,
          'durationMs': (r['duration_ms'] as num?)?.toInt() ?? 0,
          'completed': (r['completed'] as num?)?.toInt() == 1,
          'updatedAt': r['updated_at']?.toString(),
        },
    };
  }

  Future<void> saveProgress(
    String animeId,
    String episodeId,
    int positionMs, {
    int durationMs = 0,
    bool completed = false,
  }) async {
    await _db.insert(
      'progress',
      {
        'anime_id': animeId,
        'episode_id': episodeId,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'completed': completed ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearProgress(String animeId, String episodeId) async {
    await _db.delete('progress', where: 'anime_id = ? AND episode_id = ?', whereArgs: [animeId, episodeId]);
  }

  // -----------------------------------------------------------------------
  // Téléchargements (prompt 8)
  // -----------------------------------------------------------------------

  Future<void> upsertDownload(Map<String, Object?> row) async {
    await _db.insert('downloads', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> listDownloads() async =>
      _db.query('downloads', orderBy: 'updated_at DESC');

  Future<Map<String, Object?>?> getDownload(String id) async {
    final List<Map<String, Object?>> rows =
        await _db.query('downloads', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> getDownloadByVersion(String versionId) async {
    final List<Map<String, Object?>> rows =
        await _db.query('downloads', where: 'version_id = ?', whereArgs: [versionId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> deleteDownload(String id) async {
    await _db.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }

  // -----------------------------------------------------------------------
  // Registre des notifications d'épisodes (prompt 9 — règle 6)
  // -----------------------------------------------------------------------

  /// Enregistre (ou met à jour) l'état « notifié » d'un épisode, avec le
  /// nombre de qualités connues au moment de la notification — base du
  /// regroupement des qualités (règle 5) et de l'anti-doublon (règle 6).
  Future<void> markEpisodeNotified(
    String episodeId, {
    required String animeId,
    String? animeTitle,
    int seasonNumber = 1,
    int episodeNumber = 0,
    required int qualityCount,
    DateTime? notifiedAt,
  }) async {
    await _db.insert(
      'notified_episodes',
      <String, Object?>{
        'episode_id': episodeId,
        'anime_id': animeId,
        'anime_title': animeTitle,
        'season_number': seasonNumber,
        'episode_number': episodeNumber,
        'quality_count': qualityCount,
        'notified_at': (notifiedAt ?? DateTime.now()).toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Tous les épisodes notifiés : épisode → nombre de qualités signalées.
  Future<Map<String, int>> loadNotifiedQualityCounts() async {
    final List<Map<String, Object?>> rows = await _db.query('notified_episodes');
    return <String, int>{
      for (final Map<String, Object?> row in rows)
        row['episode_id']! as String: (row['quality_count'] as num?)?.toInt() ?? 1,
    };
  }

  Future<Map<String, Object?>?> getNotifiedEpisode(String episodeId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'notified_episodes',
      where: 'episode_id = ?',
      whereArgs: [episodeId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // -----------------------------------------------------------------------
  // Réglages (clé/valeur, persistés)
  // -----------------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final List<Map<String, Object?>> rows =
        await _db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> addSyncHistory(Map<String, Object?> entry) => _db.insert('sync_history', entry);

  Future<List<Map<String, Object?>>> listSyncHistory({int limit = 50}) =>
      _db.query('sync_history', orderBy: 'date DESC', limit: limit);

  /// Statistiques globales (sommes sur les sources).
  Future<Map<String, int>> aggregateStats() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery('''
      SELECT
        COALESCE(SUM(analyzed_posts), 0) AS analyzed,
        COALESCE(SUM(detected_anime), 0) AS anime,
        COALESCE(SUM(detected_episodes), 0) AS episodes,
        COALESCE(MAX(last_sync), '') AS last_sync
      FROM sources
    ''');
    final Map<String, Object?> row = rows.first;
    return {
      'analyzed': (row['analyzed'] as num?)?.toInt() ?? 0,
      'anime': (row['anime'] as num?)?.toInt() ?? 0,
      'episodes': (row['episodes'] as num?)?.toInt() ?? 0,
      'lastSyncMs': DateTime.tryParse(row['last_sync']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0,
    };
  }

  // ---------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------

  static String encodeList(List<String> values) => jsonEncode(values);

  static List<String> decodeList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>).map((Object? v) => v.toString()).toList();
    } catch (_) {
      return const [];
    }
  }
}
