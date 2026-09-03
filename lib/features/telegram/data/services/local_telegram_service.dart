import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../local/data/local_database.dart';
import '../../../notifications/models/notification_models.dart';
import '../gateway/telegram_gateway.dart';
import '../models/api_exception.dart';
import '../models/resolved_channel.dart';
import '../models/source_status.dart';
import '../models/sync_history_entry.dart';
import '../models/sync_progress.dart';
import '../models/sync_stats.dart';
import '../models/telegram_input.dart';
import '../models/telegram_message.dart';
import '../models/telegram_source.dart';
import '../models/telegram_user.dart';
import 'local_sync_service.dart';
import 'telegram_service.dart';
import 'telegram_session_manager.dart';

/// Service Telegram LOCAL : l'application dialogue directement avec
/// Telegram (TDLib embarqué), sans aucun serveur intermédiaire.
///
/// - session : TDLib (stockage chiffré) + [TelegramSessionManager] ;
/// - sources, catalogue, statistiques : [LocalDatabase] (SQLite local) ;
/// - synchronisation : [LocalSyncService] (paginée, incrémentale,
///   annulable, jamais de téléchargement de vidéos).
class LocalTelegramService extends ChangeNotifier implements TelegramService {
  LocalTelegramService({
    required TelegramGateway gateway,
    required TelegramSessionManager sessionManager,
    required LocalDatabase database,
    LocalSyncService? syncService,
    VoidCallback? onCatalogChanged,
  })  : _gateway = gateway,
        // ignore: prefer_initializing_formals
        _sessionManager = sessionManager,
        _database = database,
        _sync = syncService ??
            LocalSyncService(gateway: gateway, database: database, onCatalogChanged: onCatalogChanged) {
    _sync.addListener(_onSyncChanged);
    unawaited(_restoreSession());
  }

  final TelegramGateway _gateway;
  final TelegramSessionManager _sessionManager;
  final LocalDatabase _database;
  final LocalSyncService _sync;

  TelegramAuthState _authState = TelegramAuthState.disconnected;
  TelegramUser? _currentUser;
  String? _authError;
  List<TelegramSource> _sources = [];
  StreamSubscription<GatewayAuthState>? _gatewaySub;
  bool _disposed = false;

  void _onSyncChanged() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  bool get isBackendApi => false;

  @override
  bool get isRealTelegram => true;

  @override
  TelegramGateway? get mediaGateway => _gateway;

  @override
  String? get apiBaseUrl => null;

  // ---------------------------------------------------------------------
  // Restauration de session
  // ---------------------------------------------------------------------

  Future<void> _restoreSession() async {
    _sources = _rowsToSources(await _database.listSources());
    final bool wasConnected = await _sessionManager.wasConnected();
    if (!wasConnected) {
      _notify();
      return;
    }
    _authState = TelegramAuthState.connecting;
    _notify();
    _listenToGateway();
    try {
      await _gateway.connect();
    } on GatewayError catch (error) {
      _authError = error.message;
      _authState = TelegramAuthState.error;
      _notify();
    }
  }

  /// La base de session TDLib est chiffrée : la clé est générée une fois,
  /// conservée dans le stockage sécurisé et fournie à chaque connexion.
  Future<void> _prepareEncryption() async {
    try {
      _gateway.setEncryptionKey(await _sessionManager.ensureEncryptionKey());
    } catch (_) {
      // Sans stockage sécurisé, TDLib gère son propre chiffrement local.
    }
  }

  void _listenToGateway() {
    _gatewaySub ??= _gateway.authStates.listen((GatewayAuthState state) {
      _applyGatewayState(state);
      if (state == GatewayAuthState.connected) {
        unawaited(_loadUser());
      }
    });
    // Si le gateway est déjà connecté (restauration immédiate).
    if (_gateway.authState == GatewayAuthState.connected) {
      _applyGatewayState(_gateway.authState);
      unawaited(_loadUser());
    }
  }

  void _applyGatewayState(GatewayAuthState state) {
    switch (state) {
      case GatewayAuthState.notConnected:
        _authState = TelegramAuthState.disconnected;
      case GatewayAuthState.connecting:
        _authState = TelegramAuthState.connecting;
      case GatewayAuthState.codeRequired:
        _authState = TelegramAuthState.codeRequired;
      case GatewayAuthState.passwordRequired:
        _authState = TelegramAuthState.passwordRequired;
      case GatewayAuthState.connected:
        _authState = TelegramAuthState.connected;
        _authError = null;
      case GatewayAuthState.sessionExpired:
        _authState = TelegramAuthState.expired;
        _authError = 'Votre session Telegram a expiré ou a été révoquée. Reconnectez-vous.';
      case GatewayAuthState.error:
        _authState = TelegramAuthState.error;
        _authError = _gateway.lastError;
    }
    _notify();
  }

  Future<void> _loadUser() async {
    try {
      final GatewayUser? user = await _gateway.getMe();
      if (user == null) return;
      _currentUser = TelegramUser(
        firstName: user.firstName,
        lastName: user.lastName,
        username: user.username,
        phone: user.phone,
      );
      await _sessionManager.markConnected(true);
      _notify();
    } on GatewayError {
      // Le profil n'est pas bloquant : l'état reste « connecté ».
    }
  }

  // ---------------------------------------------------------------------
  // Authentification (flux réel)
  // ---------------------------------------------------------------------

  @override
  TelegramAuthState get authState => _authState;

  @override
  TelegramUser? get currentUser => _currentUser;

  @override
  String? get authError => _authError;

  @override
  Future<void> requestCode(String phone) async {
    _authError = null;
    _authState = TelegramAuthState.connecting;
    _notify();
    _listenToGateway();
    try {
      await _prepareEncryption();
      await _gateway.connect();
      await _gateway.requestPhone(phone.trim());
      await _sessionManager.savePhone(phone.trim());
      // L'état `codeRequired` arrive via le flux de la passerelle.
    } on GatewayError catch (error) {
      _authError = error.message;
      _authState = TelegramAuthState.error;
      _notify();
      rethrow;
    }
  }

  @override
  Future<void> verifyCode(String phone, String code) async {
    _authError = null;
    try {
      await _gateway.checkCode(code);
      // `connected` ou `passwordRequired` arrivent via le flux ; quand la
      // connexion aboutit immédiatement, le profil est chargé ici pour que
      // l'appelant dispose de l'utilisateur sans délai supplémentaire.
      if (_gateway.authState == GatewayAuthState.connected) {
        await _loadUser();
      }
    } on GatewayError catch (error) {
      _authError = error.message;
      _authState = error.isFlood ? TelegramAuthState.error : TelegramAuthState.codeRequired;
      _notify();
      rethrow;
    }
  }

  @override
  Future<void> requestPassword(String password) async {
    _authError = null;
    try {
      await _gateway.checkPassword(password);
      if (_gateway.authState == GatewayAuthState.connected) {
        await _loadUser();
      }
    } on GatewayError catch (error) {
      _authError = error.message;
      _authState = TelegramAuthState.passwordRequired;
      _notify();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    // Arrête tout travail en cours : synchronisation et tâches Telegram
    // (règle 6 du prompt 11) — les données locales (catalogue,
    // téléchargements) sont CONSERVÉES.
    _sync.cancel();
    _lastSyncSummary = null;
    try {
      await _gateway.logout();
    } on GatewayError {
      // Session déjà invalide.
    }
    await _sessionManager.clearSession();
    await _sessionManager.markConnected(false);
    _currentUser = null;
    _authError = null;
    _authState = TelegramAuthState.disconnected;
    _notify();
  }

  @override
  Future<void> refreshSession() async {
    if (_gateway.authState == GatewayAuthState.connected) {
      _applyGatewayState(GatewayAuthState.connected);
      await _loadUser();
      return;
    }
    _authError = null;
    _authState = TelegramAuthState.connecting;
    _notify();
    _listenToGateway();
    try {
      await _prepareEncryption();
      await _gateway.connect();
    } on GatewayError catch (error) {
      _authError = error.message;
      _authState = TelegramAuthState.error;
      _notify();
    }
  }

  // ---------------------------------------------------------------------
  // Sources
  // ---------------------------------------------------------------------

  @override
  List<TelegramSource> get sources => List.unmodifiable(_sources);

  @override
  Future<void> loadSources() async {
    _sources = _rowsToSources(await _database.listSources());
    _notify();
  }

  @override
  TelegramSource? sourceById(String id) {
    for (final TelegramSource source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<ResolvedChannel> resolveChannel(String input) async {
    final String trimmed = input.trim();
    // Formats : @username, https://t.me/username, https://t.me/+hash.
    bool isInvite = trimmed.contains('t.me/+') || trimmed.contains('t.me/joinchat');
    final String usernamePart;
    if (isInvite) {
      usernamePart = trimmed;
    } else {
      usernamePart = TelegramInputParser.parse(trimmed);
    }
    try {
      final GatewayChat chat = await _gateway.resolveChannel(usernamePart);
      return ResolvedChannel(
        username: chat.username ?? (isInvite ? '' : usernamePart),
        title: chat.title,
        description: chat.description,
        channelId: chat.id,
        kind: switch (chat.kind) {
          GatewayChatKind.group => ChannelKind.group,
          GatewayChatKind.private => ChannelKind.private,
          GatewayChatKind.channel => ChannelKind.channel,
        },
        memberCount: chat.memberCount,
        inviteHash: chat.inviteHash,
      );
    } on GatewayError catch (error) {
      if (error.code == 403 || error.message.contains('accessible')) {
        throw ApiException(ApiErrorKind.inaccessible, message: error.message, code: 'SOURCE_INACCESSIBLE');
      }
      if (error.message.contains('introuvable')) {
        throw ApiException(ApiErrorKind.notFound, message: error.message, code: 'SOURCE_NOT_FOUND');
      }
      throw ApiException(ApiErrorKind.telegram, message: error.message);
    }
  }

  @override
  Future<TelegramSource> addSource({
    required String name,
    required String username,
    String? channelId,
    String kind = 'channel',
    String? inviteHash,
  }) async {
    // Règle §8 : une chaîne de caractères n'est JAMAIS considérée comme une
    // source valide sans vérification réelle — la source est d'abord RÉSOLUE
    // via Telegram (canal inaccessible/inexistant = ajout refusé), et son
    // identifiant réel est conservé quand disponible.
    final ResolvedChannel resolved = await resolveChannel(username);
    final int? realChatId = resolved.channelId ?? (channelId == null ? null : int.tryParse(channelId));
    final String id = 'src-$username-${DateTime.now().millisecondsSinceEpoch}';
    final Map<String, Object?> row = {
      'id': id,
      'name': name,
      'username': resolved.username.isNotEmpty ? resolved.username : username,
      'kind': kind,
      'chat_id': realChatId,
      'invite_hash': inviteHash,
      'status': 'active',
      'sync_enabled': 1,
    };
    await _database.upsertSource(row);
    await loadSources();
    return sourceById(id)!;
  }

  @override
  Future<void> removeSource(String sourceId) async {
    await _database.deleteSource(sourceId);
    await loadSources();
  }

  @override
  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    final TelegramSource? source = sourceById(sourceId);
    if (source == null) return;
    await _database.upsertSource({
      'id': source.id,
      'name': source.name,
      'username': source.username,
      'kind': source.kind,
      'status': enabled ? 'active' : 'disabled',
      'sync_enabled': enabled ? 1 : 0,
    });
    await loadSources();
  }

  // ---------------------------------------------------------------------
  // Publications (paginées)
  // ---------------------------------------------------------------------

  @override
  Future<List<TelegramMessage>> fetchMessages(String sourceId, {int limit = 20}) async {
    final TelegramSource? source = sourceById(sourceId);
    if (source == null) throw const ApiException(ApiErrorKind.notFound);
    final int? chatId = source.telegramChannelId;
    final GatewayChat chat;
    if (chatId != null) {
      chat = await _resolveStored(source, chatId);
    } else {
      chat = await _gateway.resolveChannel(source.username);
    }
    final List<GatewayMessage> messages = await _gateway.getMessages(chatId: chat.id!, limit: limit);
    return [
      for (final GatewayMessage message in messages)
        TelegramMessage(
          messageId: message.messageId,
          channelUsername: source.username,
          channelId: message.chatId,
          date: message.date,
          text: message.text,
          mediaType: _mediaTypeFrom(message.mediaType),
          fileName: message.fileName,
          fileSize: message.fileSize,
          messageLink: telegramMessageLink(
            chatId: message.chatId,
            messageId: message.messageId,
            username: chat.username,
            kind: chat.kind,
          ),
        ),
    ];
  }

  Future<GatewayChat> _resolveStored(TelegramSource source, int chatId) async {
    final List<GatewayChat> chats = await _gateway.getChannels();
    for (final GatewayChat chat in chats) {
      if (chat.id == chatId) return chat;
    }
    return GatewayChat(id: chatId, title: source.name, username: source.username);
  }

  // ---------------------------------------------------------------------
  // Synchronisation
  // ---------------------------------------------------------------------

  @override
  SyncStats get stats {
    final LocalSyncState state = _sync.state;
    // Statistiques cumulées des sources (persistées).
    final int analyzed = _sources.fold<int>(0, (int sum, TelegramSource s) => sum + s.analyzedPosts);
    final int anime = _sources.fold<int>(0, (int sum, TelegramSource s) => sum + s.detectedAnime);
    final int episodes = _sources.fold<int>(0, (int sum, TelegramSource s) => sum + s.detectedEpisodes);
    DateTime? lastSync;
    for (final TelegramSource source in _sources) {
      if (source.lastSync != null && (lastSync == null || source.lastSync!.isAfter(lastSync))) {
        lastSync = source.lastSync;
      }
    }
    return SyncStats(
      analyzedPosts: analyzed,
      detectedAnime: anime,
      detectedEpisodes: episodes,
      duplicatesGrouped: 0,
      newEpisodes: state.newEpisodes,
      lastSync: lastSync,
    );
  }

  @override
  bool get isSyncing => _sync.isRunning;

  @override
  SyncProgress? get currentProgress {
    if (!_sync.isRunning && _sync.state.phase != LocalSyncPhase.done) return null;
    final LocalSyncState state = _sync.state;
    return SyncProgress(
      fraction: state.fraction,
      phase: state.message ?? '',
      analyzedPosts: state.analyzed,
      totalPosts: state.fetched,
    );
  }

  @override
  List<SyncHistoryEntry> get history => _history;

  List<SyncHistoryEntry> _history = [];

  @override
  Future<void> loadStats() async {
    _history = [
      for (final Map<String, Object?> row in await _database.listSyncHistory(limit: 50))
        SyncHistoryEntry(
          id: row['id'].toString(),
          date: DateTime.tryParse(row['date']?.toString() ?? '') ?? DateTime.now(),
          success: (row['success'] as num?)?.toInt() == 1,
          analyzedPosts: (row['analyzed_posts'] as num?)?.toInt() ?? 0,
          newEpisodes: (row['new_episodes'] as num?)?.toInt() ?? 0,
        ),
    ];
    _notify();
  }

  @override
  SourceStatus? simulatedSourceStatus;

  SyncRunSummary? _lastSyncSummary;

  @override
  SyncRunSummary? get lastSyncSummary => _lastSyncSummary;

  /// Branché par l'application (centre de notifications — prompt 9).
  @override
  void Function(SyncRunSummary summary)? onSyncCompleted;

  /// Synchronise les sources. Règle 16 : sans cible précise, SEULES les
  /// sources ACTIVÉES sont synchronisées ; une source désactivée n'est
  /// jamais interrogée. Après la passe, le résumé RÉEL est exposé via
  /// [lastSyncSummary] (règle 21) et transmis au centre de notifications
  /// via [onSyncCompleted] (règle 4).
  @override
  Future<void> syncSource({String? sourceId}) async {
    if (_authState != TelegramAuthState.connected && _gateway.authState != GatewayAuthState.connected) {
      throw const ApiException(ApiErrorKind.unauthorized, message: 'Compte Telegram non connecté. Reconnectez-vous.');
    }
    final List<TelegramSource> targets = sourceId == null
        ? _sources.where((TelegramSource s) => s.syncEnabled).toList()
        : _sources.where((TelegramSource s) => s.id == sourceId).toList();

    int sourcesAnalyzed = 0;
    int analyzed = 0;
    int newEpisodes = 0;
    int newQualities = 0;
    int errors = 0;
    bool cancelled = false;
    final List<String> errorMessages = <String>[];
    final List<SyncRunEpisode> updates = <SyncRunEpisode>[];

    for (final TelegramSource source in targets) {
      final Map<String, Object?>? row = await _database.getSource(source.id);
      if (row == null) continue;
      final LocalSyncResult result = await _sync.syncSource(row);
      await loadSources();
      await loadStats();
      if (result.errorMessage != null) {
        errors += 1;
        errorMessages.add(result.errorMessage!);
        // Synchronisation ciblée : l'échec remonte comme avant (message
        // clair à l'utilisateur), le résumé reste enregistré.
        if (sourceId != null) {
          _recordSummary(
            sourcesAnalyzed: sourcesAnalyzed,
            newMessages: analyzed,
            newEpisodes: newEpisodes,
            newQualities: newQualities,
            errors: errors,
            errorMessages: errorMessages,
            cancelled: cancelled,
            episodes: updates,
          );
          throw ApiException(ApiErrorKind.telegram, message: result.errorMessage);
        }
        continue;
      }
      sourcesAnalyzed += 1;
      analyzed += result.analyzed;
      newEpisodes += result.newEpisodes;
      newQualities += result.grouped;
      cancelled = cancelled || result.cancelled;
      updates.addAll(result.episodeUpdates);
    }

    _recordSummary(
      sourcesAnalyzed: sourcesAnalyzed,
      newMessages: analyzed,
      newEpisodes: newEpisodes,
      newQualities: newQualities,
      errors: errors,
      errorMessages: errorMessages,
      cancelled: cancelled,
      episodes: updates,
    );

    // Toutes les sources ont échoué : remonter une erreur globale claire
    // (règle 25) plutôt qu'un résumé « réussi » trompeur.
    if (sourceId == null && targets.isNotEmpty && errors > 0 && sourcesAnalyzed == 0) {
      throw ApiException(ApiErrorKind.telegram, message: errorMessages.join('\n'));
    }
  }

  void _recordSummary({
    required int sourcesAnalyzed,
    required int newMessages,
    required int newEpisodes,
    required int newQualities,
    required int errors,
    required List<String> errorMessages,
    required bool cancelled,
    required List<SyncRunEpisode> episodes,
  }) {
    final SyncRunSummary summary = SyncRunSummary(
      finishedAt: DateTime.now(),
      sourcesAnalyzed: sourcesAnalyzed,
      newMessages: newMessages,
      newEpisodes: newEpisodes,
      newQualities: newQualities,
      errors: errors,
      errorMessages: errorMessages,
      cancelled: cancelled,
      episodes: episodes,
    );
    _lastSyncSummary = summary;
    _notify();
    try {
      onSyncCompleted?.call(summary);
    } catch (_) {
      // Un récepteur défaillant ne casse jamais la synchronisation.
    }
  }

  @override
  Future<void> syncAll() async {
    await syncSource();
  }

  @override
  Future<void> cancelSync() async {
    _sync.cancel();
  }

  // ---------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------

  List<TelegramSource> _rowsToSources(List<Map<String, Object?>> rows) => [
        for (final Map<String, Object?> row in rows)
          TelegramSource(
            id: row['id']! as String,
            name: row['name']! as String,
            username: row['username']! as String,
            kind: row['kind'] as String? ?? 'channel',
            description: row['description'] as String?,
            status: switch (row['status']) {
              'disabled' => SourceStatus.disabled,
              'error' => SourceStatus.error,
              'syncing' => SourceStatus.syncing,
              _ => SourceStatus.active,
            },
            lastSync: DateTime.tryParse(row['last_sync']?.toString() ?? ''),
            analyzedPosts: (row['analyzed_posts'] as num?)?.toInt() ?? 0,
            detectedAnime: (row['detected_anime'] as num?)?.toInt() ?? 0,
            detectedEpisodes: (row['detected_episodes'] as num?)?.toInt() ?? 0,
            syncEnabled: (row['sync_enabled'] as num?)?.toInt() != 0,
            telegramChannelId: (row['chat_id'] as num?)?.toInt(),
          ),
      ];

  static TelegramMediaType _mediaTypeFrom(String mediaType) => switch (mediaType) {
        'video' => TelegramMediaType.video,
        'image' => TelegramMediaType.image,
        'document' => TelegramMediaType.document,
        _ => TelegramMediaType.text,
      };

  @override
  void dispose() {
    _disposed = true;
    _gatewaySub?.cancel();
    _sync.removeListener(_onSyncChanged);
    unawaited(_gateway.close());
    super.dispose();
  }
}
