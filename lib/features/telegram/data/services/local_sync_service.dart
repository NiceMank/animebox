import 'package:flutter/foundation.dart';

import '../../../analyzer/engine.dart';
import '../../../analyzer/models.dart';
import '../../../local/data/local_database.dart';
import '../gateway/telegram_gateway.dart';

/// Phases d'une synchronisation locale.
enum LocalSyncPhase { fetching, analyzing, done }

/// État courant de la synchronisation (progression affichable).
class LocalSyncState {
  const LocalSyncState({
    required this.phase,
    this.fetched = 0,
    this.analyzed = 0,
    this.newEpisodes = 0,
    this.sourceId,
    this.message,
  });

  final LocalSyncPhase phase;
  final int fetched;
  final int analyzed;
  final int newEpisodes;
  final String? sourceId;
  final String? message;

  double? get fraction {
    if (phase == LocalSyncPhase.done) return 1;
    if (phase == LocalSyncPhase.fetching || fetched == 0) return null;
    return analyzed / fetched;
  }
}

/// Résultat d'une passe de synchronisation.
class LocalSyncResult {
  const LocalSyncResult({
    this.analyzed = 0,
    this.newEpisodes = 0,
    this.grouped = 0,
    this.cancelled = false,
    this.errorMessage,
  });

  final int analyzed;
  final int newEpisodes;
  final int grouped;
  final bool cancelled;
  final String? errorMessage;
}

/// Synchronisation LOCALE : Telegram → messages → analyse → classement →
/// base locale → catalogue. Aucun serveur distant n'est impliqué.
///
/// - Première synchronisation : limite raisonnable (défaut 100 messages) ;
/// - synchronisations suivantes : INC RÉMENTALES (curseur = dernier message
///   analysé) — batterie, données mobiles et temps de traitement préservés ;
/// - récupération paginée (50 messages par page, jamais tout en mémoire) ;
/// - traitement par lots et arrêt propre (annulation entre deux pages).
class LocalSyncService extends ChangeNotifier {
  LocalSyncService({
    required this.gateway,
    required this.database,
    RuleBasedAnalyzer? analyzer,
    this.initialMessageLimit = 100,
    this.pageSize = 50,
    this.onCatalogChanged,
  }) : analyzer = analyzer ?? RuleBasedAnalyzer();

  final TelegramGateway gateway;
  final LocalDatabase database;
  final RuleBasedAnalyzer analyzer;

  /// Limite de la PREMIÈRE synchronisation (messages récents).
  final int initialMessageLimit;

  /// Taille des pages de récupération.
  final int pageSize;

  /// Notifié après chaque commit (le dépôt recharge le catalogue).
  final VoidCallback? onCatalogChanged;

  bool _running = false;
  bool _cancelRequested = false;
  LocalSyncState _state = const LocalSyncState(phase: LocalSyncPhase.done);

  bool get isRunning => _running;
  LocalSyncState get state => _state;

  /// Demande un arrêt propre (entre deux lots).
  void cancel() {
    _cancelRequested = true;
    _setState(_stateWith(message: 'Annulation demandée…'));
  }

  /// Synchronise une source (row SQLite) et renvoie le résultat.
  Future<LocalSyncResult> syncSource(Map<String, Object?> source) async {
    if (_running) {
      return const LocalSyncResult(errorMessage: 'Une synchronisation est déjà en cours.');
    }
    _running = true;
    _cancelRequested = false;
    final String sourceId = source['id']! as String;
    _setState(LocalSyncState(phase: LocalSyncPhase.fetching, sourceId: sourceId, message: 'Récupération des messages…'));

    try {
      return await _runSync(source);
    } finally {
      _running = false;
      if (_state.phase != LocalSyncPhase.done) {
        _setState(LocalSyncState(
          phase: LocalSyncPhase.done,
          sourceId: sourceId,
          fetched: _state.fetched,
          analyzed: _state.analyzed,
          newEpisodes: _state.newEpisodes,
        ));
      }
    }
  }

  Future<LocalSyncResult> _runSync(Map<String, Object?> source) async {
    final String sourceId = source['id']! as String;
    final String username = (source['username'] as String?) ?? '';
    final int cursor = (source['last_message_id'] as num?)?.toInt() ?? 0;
    final int? storedChatId = (source['chat_id'] as num?)?.toInt();

    // 1. Résoudre la conversation (re-vérifie l'accessibilité).
    final GatewayChat chat;
    try {
      chat = storedChatId != null && storedChatId != 0
          ? await _chatById(storedChatId, username)
          : await gateway.resolveChannel(username);
    } on GatewayError catch (error) {
      return await _fail(sourceId, error.message);
    }

    // 2. Récupération paginée (nouvelles pages tant que nécessaire).
    final List<GatewayMessage> collected = [];
    int? fromMessageId;
    while (!_cancelRequested) {
      final List<GatewayMessage> page = await _fetchPage(chat.id!, fromMessageId);
      if (page.isEmpty) break;
      collected.addAll(page);
      _setState(_stateWith(fetched: collected.length, message: 'Messages récupérés : ${collected.length}'));
      // Tous les messages de la page sont antérieurs au curseur → stop.
      final int oldest = page.map((GatewayMessage m) => m.messageId).reduce((int a, int b) => a < b ? a : b);
      if (cursor > 0 && oldest <= cursor) break;
      if (cursor == 0 && collected.length >= initialMessageLimit) break; // première synchro limitée
      if (collected.length >= 2000) break; // plafond de sécurité absolu
      fromMessageId = oldest;
    }
    if (_cancelRequested) {
      await database.addSyncHistory({
        'source_id': sourceId,
        'date': DateTime.now().toIso8601String(),
        'success': 0,
        'analyzed_posts': 0,
        'new_episodes': 0,
      });
      return const LocalSyncResult(cancelled: true);
    }

    // 3. Analyse + classement (par lots, en mémoire maîtrisée).
    int analyzed = 0;
    int newEpisodes = 0;
    int grouped = 0;
    int maxMessageId = cursor;
    final Map<String, AnalysisResult> accepted = {};
    for (final GatewayMessage message in collected) {
      if (_cancelRequested) return LocalSyncResult(cancelled: true, analyzed: analyzed, newEpisodes: newEpisodes, grouped: grouped);
      // Incrémental : seuls les messages POSTÉRIEURS au curseur sont analysés.
      if (cursor > 0 && message.messageId <= cursor) continue;
      analyzed += 1;
      if (message.messageId > maxMessageId) maxMessageId = message.messageId;
      final AnalysisResult result = analyzer.analyze({
        'file_name': message.fileName,
        'text': message.text,
        'file_size': message.fileSize,
        'mime_type': message.mimeType,
        'duration': message.duration,
        'width': message.width,
        'height': message.height,
        'media_type': message.mediaType,
        'telegram_channel_id': chat.id?.toString(),
        'telegram_channel_username': username,
        'telegram_message_id': message.messageId,
        'telegram_message_link': telegramMessageLink(
          chatId: message.chatId,
          messageId: message.messageId,
          username: chat.username,
          kind: chat.kind,
        ),
      });
      // Jamais classé aveuglément : seules les analyses suffisamment sûres
      // alimentent le catalogue.
      if (kIngestibleStatuses.contains(result.status) && result.titleKey != null) {
        accepted['${message.messageId}'] = result;
      }
      _setState(_stateWith(analyzed: analyzed, message: 'Analyse : $analyzed / ${collected.length}'));
    }

    // 4. Stockage local (transactionnel) + mise à jour du curseur.
    if (accepted.isNotEmpty) {
      final (int episodes, int merged) = await _persist(sourceId, chat, accepted.values.toList());
      newEpisodes = episodes;
      grouped = merged;
    }
    final int updatedCursor = maxMessageId > cursor ? maxMessageId : cursor;
    final Map<String, Object?> updated = Map<String, Object?>.from(source)
      ..['last_sync'] = DateTime.now().toIso8601String()
      ..['last_message_id'] = updatedCursor
      ..['chat_id'] = chat.id
      ..['status'] = 'active'
      ..['analyzed_posts'] = ((source['analyzed_posts'] as num?)?.toInt() ?? 0) + analyzed
      ..['detected_episodes'] = ((source['detected_episodes'] as num?)?.toInt() ?? 0) + newEpisodes;
    await database.upsertSource(updated);
    await database.addSyncHistory({
      'source_id': sourceId,
      'date': DateTime.now().toIso8601String(),
      'success': 1,
      'analyzed_posts': analyzed,
      'new_episodes': newEpisodes,
    });
    onCatalogChanged?.call();
    _setState(_stateWith(
      newEpisodes: _state.newEpisodes + newEpisodes,
      message: 'Synchronisation terminée.',
      phase: LocalSyncPhase.done,
    ));
    return LocalSyncResult(analyzed: analyzed, newEpisodes: newEpisodes, grouped: grouped);
  }

  Future<GatewayChat> _chatById(int chatId, String username) async {
    // getChatHistory échouera si le compte n'a plus accès à la
    // conversation : l'erreur remonte telle quelle (message clair).
    await gateway.getMessages(chatId: chatId, limit: 1);
    final List<GatewayChat> chats = await gateway.getChannels();
    for (final GatewayChat chat in chats) {
      if (chat.id == chatId) return chat;
    }
    return GatewayChat(id: chatId, title: username, username: username);
  }

  Future<List<GatewayMessage>> _fetchPage(int chatId, int? fromMessageId) async {
    try {
      return await gateway.getMessages(chatId: chatId, limit: pageSize, fromMessageId: fromMessageId);
    } on GatewayError {
      rethrow;
    }
  }

  Future<LocalSyncResult> _fail(String sourceId, String message) async {
    try {
      final Map<String, Object?>? row = await database.getSource(sourceId);
      if (row != null) {
        await database.upsertSource(Map<String, Object?>.from(row)..['status'] = 'error');
      }
      await database.addSyncHistory({
        'source_id': sourceId,
        'date': DateTime.now().toIso8601String(),
        'success': 0,
        'analyzed_posts': 0,
        'new_episodes': 0,
      });
    } catch (_) {
      // L'échec d'historisation ne masque jamais l'erreur initiale.
    }
    _setState(_stateWith(message: message, phase: LocalSyncPhase.done));
    return LocalSyncResult(errorMessage: message);
  }

  /// Stocke les analyses acceptées : anime → saison → épisode → versions.
  /// Les qualités d'un même épisode sont regroupées sur UNE fiche épisode ;
  /// aucune version n'est supprimée (une par publication).
  Future<(int, int)> _persist(
    String sourceId,
    GatewayChat chat,
    List<AnalysisResult> results,
  ) async {
    int newEpisodes = 0;
    int merged = 0;
    // Les insertions sont groupées en fin de passe : on suit les épisodes
    // déjà vus pour compter les NOUVEAUX épisodes sans doublons.
    final Set<String> seenEpisodeIds = {};
    final List<Map<String, Object?>> animeRows = [];
    final List<Map<String, Object?>> seasonRows = [];
    final List<Map<String, Object?>> episodeRows = [];
    final List<Map<String, Object?>> versionRows = [];

    for (final AnalysisResult result in results) {
      final String animeId = _slug(result.titleKey!);
      final int seasonNumber = result.season ?? 1;
      final int? episodeNumber = result.episode;

      // L'animé existe-t-il déjà ?
      final Map<String, Object?>? existingAnime = await database.getAnime(animeId);
      if (existingAnime == null) {
        animeRows.add({
          'id': animeId,
          'title': result.title ?? result.titleKey,
          'canonical_title': result.title,
          'original_title': result.originalTitle,
          'description': '',
          'genres': '[]',
          'year': result.releaseYear,
          'source': chat.username ?? chat.title,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      final String seasonId = '$animeId-s$seasonNumber';
      Map<String, Object?>? seasonRow = await database.getSeason(seasonId);
      if (seasonRow == null) {
        seasonRow = {'id': seasonId, 'anime_id': animeId, 'number': seasonNumber};
        seasonRows.add(seasonRow);
      }

      if (episodeNumber == null) continue; // spécial sans numéro : non classé
      final String episodeId = '$seasonId-e$episodeNumber';
      final bool episodeExists = await database.hasEpisode(episodeId);
      if (!episodeExists && !seenEpisodeIds.contains(episodeId)) {
        episodeRows.add({
          'id': episodeId,
          'season_id': seasonId,
          'number': episodeNumber,
          'kind': 'regular',
          'title': null, // jamais de titre inventé
          'date': DateTime.now().toIso8601String(),
          'is_new': 1,
        });
        seenEpisodeIds.add(episodeId);
        newEpisodes += 1;
      } else {
        merged += 1; // une qualité de plus sur un épisode existant/regroupé
      }

      // Une version par publication (aucune suppression).
      versionRows.add({
        'id': '$episodeId-v${result.telegramMessageId}',
        'episode_id': episodeId,
        'quality': result.quality,
        'quality_rank': result.qualityRank,
        'language': result.language == 'unknown' ? null : result.language,
        'subtitles': result.subtitles,
        'resolution': result.width != null && result.height != null ? '${result.width}x${result.height}' : null,
        'size': result.fileSize,
        'media_type': result.mediaType,
        'file_name': result.fileName,
        'duration': result.duration,
        'width': result.width,
        'height': result.height,
        'telegram_channel_id': result.telegramChannelId,
        'telegram_channel_username': result.telegramChannelUsername,
        'telegram_message_id': result.telegramMessageId,
        'telegram_message_link': result.telegramMessageLink,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    await database.saveCatalogGraph(
      anime: animeRows,
      seasons: seasonRows,
      episodes: episodeRows,
      versions: versionRows,
    );
    return (newEpisodes, merged);
  }

  String _slug(String titleKey) {
    const String accented = 'áàâäãåéèêëíìîïóòôöõúùûüçñ';
    const String plain = 'aaaaaaeeeeiiiiooooouuuucn';
    final StringBuffer buffer = StringBuffer();
    for (final int rune in titleKey.toLowerCase().runes) {
      final String character = String.fromCharCode(rune);
      final int index = accented.indexOf(character);
      if (character == ' ') {
        buffer.write('-');
      } else if (index >= 0) {
        buffer.write(plain[index]);
      } else if (RegExp(r'[a-z0-9-]').hasMatch(character)) {
        buffer.write(character);
      }
    }
    return buffer.toString();
  }

  LocalSyncState _stateWith({
    LocalSyncPhase? phase,
    int? fetched,
    int? analyzed,
    int? newEpisodes,
    String? message,
  }) =>
      LocalSyncState(
        phase: phase ?? _state.phase,
        fetched: fetched ?? _state.fetched,
        analyzed: analyzed ?? _state.analyzed,
        newEpisodes: newEpisodes ?? _state.newEpisodes,
        sourceId: _state.sourceId,
        message: message ?? _state.message,
      );

  void _setState(LocalSyncState state) {
    _state = state;
    notifyListeners();
  }
}
