import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/tdlib.dart';

import 'telegram_gateway.dart';

/// Implémentation réelle de la passerelle Telegram, adossée à TDLib —
/// la bibliothèque officielle Telegram (binairies embarquées sur Android).
///
/// L'application dialogue DIRECTEMENT avec les serveurs Telegram :
/// aucune donnée (session, messages, fichiers) ne transite par un
/// serveur intermédiaire. La session est conservée par TDLib dans son
/// propre stockage chiffré (répertoire privé de l'application).
class TdlibTelegramGateway implements TelegramGateway {
  TdlibTelegramGateway({
    required this.apiId,
    required this.apiHash,
    this.databaseDirectory,
    this.filesDirectory,
    this.encryptionKey,
    this.timeout = const Duration(seconds: 20),
  });

  /// Identifiants d'application Telegram (my.telegram.org) — fournis à la
  /// compilation via --dart-define, jamais codés en dur dans les écrans
  /// ni écrits dans les logs.
  final int apiId;
  final String apiHash;

  /// Répertoires TDLib (session + fichiers) — défaut : documents privés.
  String? databaseDirectory;
  String? filesDirectory;

  /// Clé de chiffrement de la base TDLib (générée et conservée dans le
  /// stockage sécurisé par [TelegramSessionManager]).
  String? encryptionKey;

  final Duration timeout;

  int? _clientId;
  bool _running = false;
  bool _wasConnected = false;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  int _extraCounter = 0;

  GatewayAuthState _authState = GatewayAuthState.notConnected;
  String? _lastError;
  final StreamController<GatewayAuthState> _authController =
      StreamController<GatewayAuthState>.broadcast();
  final StreamController<GatewayFileSnapshot> _fileUpdates =
      StreamController<GatewayFileSnapshot>.broadcast();

  @override
  Stream<GatewayFileSnapshot> get fileUpdates => _fileUpdates.stream;

  @override
  GatewayAuthState get authState => _authState;

  @override
  Stream<GatewayAuthState> get authStates => _authController.stream;

  @override
  String? get lastError => _lastError;

  // ---------------------------------------------------------------------
  // Cycle de vie
  // ---------------------------------------------------------------------

  @override
  Future<void> connect() async {
    if (_clientId != null) return;
    final TdPlugin plugin = TdPlugin.instance;
    // TOUT échec de démarrage (bibliothèque native absente, ABI, paramétrage)
    // devient une erreur VISIBLE à l'écran — jamais de blocage silencieux
    // sans réseau (cause fréquente de « la connexion ne fait rien »).
    try {
      await TdPlugin.initialize();

      final int clientId = plugin.tdJsonClientCreate();
      if (clientId <= 0) {
        _lastError = 'Impossible de démarrer le client Telegram sur cet appareil.';
        _setState(GatewayAuthState.error);
        return;
      }
      _clientId = clientId;
      _running = true;
      _lastError = null;
      _setState(GatewayAuthState.connecting);
      // La boucle de réception tourne tant que le client existe.
      unawaited(_pumpLoop(plugin));

      // La session restaurée ne doit jamais être lisible en clair :
      // on fournit la clé de chiffrement AVANT tout autre échange.
      if (encryptionKey != null && encryptionKey!.isNotEmpty) {
        await _request('setDatabaseEncryptionKey', {
          'new_encryption_key': encryptionKey,
        });
      }
      final String database = databaseDirectory ??= await _resolveDirectory('tdlib_db');
      final String files = filesDirectory ??= await _resolveDirectory('tdlib_files');
      await _request('setTdlibParameters', {
        'api_id': apiId,
        'api_hash': apiHash,
        'system_language_code': 'fr',
        'device_model': 'AnimeBox',
        'system_version': 'Android',
        'application_version': '1.0.0',
        'database_directory': database,
        'files_directory': files,
        'enable_storage_optimizer': true,
        'ignore_file_names': false,
      });
    } on GatewayError catch (error) {
      _lastError = error.message;
      _setState(GatewayAuthState.error);
    } catch (_) {
      // Exception hors protocole (bibliothèque native non chargée, etc.) :
      // visible, jamais avalée.
      _lastError = 'Le client Telegram n\'a pas pu démarrer sur cet appareil. Relancez l\'application.';
      _setState(GatewayAuthState.error);
    }
  }

  Future<String> _resolveDirectory(String name) async {
    // path_provider renvoie le chemin des documents de l'application
    // (espace privé sur Android) — sans dépendre de dart:io.
    final String base = (await getApplicationDocumentsDirectory()).path;
    return p.join(base, name);
  }

  @override
  Future<void> close() async {
    if (_clientId == null) return;
    try {
      // « close » sauvegarde l'état TDLib : la session reste valide.
      await _request('close', {});
    } on GatewayError {
      // Le client peut déjà être fermé.
    }
    _destroy();
  }

  @override
  void setEncryptionKey(String key) => encryptionKey = key;

  @override
  Future<void> logout() async {
    if (_clientId == null) return;
    try {
      await _request('logOut', {});
      // logOut détruit la session ; TDLib retourne à l'attente du numéro.
    } on GatewayError {
      // Session déjà invalide : rien d'autre à faire.
    }
    _wasConnected = false;
  }

  void _destroy() {
    _running = false;
    final int? clientId = _clientId;
    _clientId = null;
    if (clientId != null) {
      try {
        TdPlugin.instance.tdJsonClientDestroy(clientId);
      } catch (_) {
        // Le plugin peut déjà être arrêté.
      }
    }
    for (final Completer<Map<String, dynamic>> completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(const GatewayError('Client Telegram fermé.'));
      }
    }
    _pending.clear();
    _setState(GatewayAuthState.notConnected);
  }

  // ---------------------------------------------------------------------
  // Réception TDLib (boucle unique — protocole tdjson)
  // ---------------------------------------------------------------------

  Future<void> _pumpLoop(TdPlugin plugin) async {
    int consecutiveFailures = 0;
    while (_running) {
      final int? clientId = _clientId;
      if (clientId == null) return;
      String? raw;
      try {
        raw = plugin.tdJsonClientReceive(clientId, 0.5);
        consecutiveFailures = 0;
      } catch (_) {
        // Plusieurs échecs natifs de suite = le client est inutilisable :
        // on le signale au lieu de boucler silencieusement.
        consecutiveFailures += 1;
        if (consecutiveFailures >= 3) {
          _lastError = 'Le client Telegram s\'est interrompu. Relancez l\'application.';
          _setState(GatewayAuthState.error);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }
      if (raw == null || raw.isEmpty) continue;
      Map<String, dynamic>? json;
      try {
        json = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final String type = json['@type']?.toString() ?? '';
      final Object? extra = json['@extra'];
      if (type == 'error') {
        final GatewayError error = _errorFromTd(json);
        if (extra is String) {
          _pending.remove(extra)?.completeError(error);
        } else {
          // Erreur générale de TDLib (paramétrage, API invalidée, interdiction
          // réseau, etc.) : VISIBLE à l'écran, jamais silencieuse — sinon
          // l'utilisateur attend indéfiniment sans qu'aucun octet ne parte.
          _lastError = error.message;
          _setState(GatewayAuthState.error);
        }
        continue;
      }
      if (extra is String) {
        _pending.remove(extra)?.complete(json);
        continue;
      }
      await _handleUpdate(json);
    }
  }

  Future<void> _handleUpdate(Map<String, dynamic> update) async {
    if (update['@type'] == 'updateAuthorizationState') {
      await _applyAuthorizationState(
        (update['authorization_state'] as Map<String, dynamic>?)?['@type']?.toString(),
      );
      return;
    }
    if (update['@type'] == 'updateFile') {
      final Map<String, dynamic>? file = update['file'] as Map<String, dynamic>?;
      if (file != null) {
        final GatewayFileSnapshot snapshot = GatewayFileSnapshot.fromTd(file);
        if (!_fileUpdates.isClosed) _fileUpdates.add(snapshot);
      }
    }
  }

  Future<void> _applyAuthorizationState(String? type) async {
    if (type == 'authorizationStateWaitTdlibParameters') {
      _setState(GatewayAuthState.connecting);
      return;
    }
    if (type == 'authorizationStateWaitEncryptionKey') {
      if (encryptionKey != null && encryptionKey!.isNotEmpty) {
        try {
          await _request('setDatabaseEncryptionKey', {
            'new_encryption_key': encryptionKey,
          });
        } on GatewayError {
          _lastError = 'Impossible de déchiffrer la session enregistrée.';
          _setState(GatewayAuthState.error);
        }
      }
      return;
    }
    if (type == 'authorizationStateWaitPhoneNumber') {
      // Déjà connecté auparavant → la session a été révoquée à distance.
      _setState(_wasConnected ? GatewayAuthState.sessionExpired : GatewayAuthState.notConnected);
      return;
    }
    if (type == 'authorizationStateWaitCode') {
      _setState(GatewayAuthState.codeRequired);
      return;
    }
    if (type == 'authorizationStateWaitPassword') {
      _setState(GatewayAuthState.passwordRequired);
      return;
    }
    if (type == 'authorizationStateWaitOtherDeviceConfirmation') {
      _lastError = 'Confirmez la connexion depuis un autre appareil Telegram.';
      _setState(GatewayAuthState.codeRequired);
      return;
    }
    if (type == 'authorizationStateWaitEmailAddress' || type == 'authorizationStateWaitEmailCode') {
      _lastError = 'Telegram demande une confirmation par e-mail.';
      _setState(GatewayAuthState.codeRequired);
      return;
    }
    if (type == 'authorizationStateWaitRegistration') {
      _lastError = 'Compte Telegram non enregistré : créez d\'abord un compte.';
      _setState(GatewayAuthState.codeRequired);
      return;
    }
    if (type == 'authorizationStateReady') {
      _wasConnected = true;
      _lastError = null;
      _setState(GatewayAuthState.connected);
      return;
    }
    if (type == 'authorizationStateLoggingOut') {
      _setState(GatewayAuthState.connecting);
      return;
    }
    if (type == 'authorizationStateClosed') {
      _setState(GatewayAuthState.notConnected);
    }
  }

  // ---------------------------------------------------------------------
  // Requêtes TDLib
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, Object?> params, {
    Duration? timeout,
  }) async {
    final int? clientId = _clientId;
    if (clientId == null) {
      throw const GatewayError('Client Telegram non démarré.');
    }
    final String extra = 'req-${++_extraCounter}';
    final Completer<Map<String, dynamic>> completer = Completer<Map<String, dynamic>>();
    _pending[extra] = completer;
    TdPlugin.instance.tdJsonClientSend(
      clientId,
      jsonEncode({'@type': method, '@extra': extra, ...params}),
    );
    return completer.future.timeout(timeout ?? this.timeout, onTimeout: () {
      _pending.remove(extra);
      throw const GatewayError('Telegram met trop de temps à répondre. Réessayez.');
    });
  }

  GatewayError _errorFromTd(Map<String, dynamic> json) {
    final int code = (json['code'] as num?)?.toInt() ?? 0;
    final String message = json['message']?.toString() ?? '';
    // Messages compréhensibles — jamais de trace technique brute.
    if (code == 400 && message.contains('PHONE_CODE_INVALID')) {
      return const GatewayError('Code de connexion incorrect.');
    }
    if (code == 400 && message.contains('PHONE_CODE_EXPIRED')) {
      return const GatewayError('Code de connexion expiré. Renvoyez un code.');
    }
    if (code == 400 && message.contains('PASSWORD_HASH_INVALID')) {
      return const GatewayError('Mot de passe 2FA incorrect.');
    }
    if (code == 400 && message.contains('PHONE_NUMBER_INVALID')) {
      return const GatewayError('Numéro de téléphone invalide.');
    }
    if (code == 400 && message.contains('USERNAME_NOT_OCCUPIED')) {
      return const GatewayError('Source introuvable sur Telegram.');
    }
    if (code == 400 && message.contains('USERNAME_INVALID')) {
      return const GatewayError('Format de source invalide.');
    }
    if (code == 403) {
      return const GatewayError('Ce canal n\'est pas accessible avec ce compte Telegram.');
    }
    if (code == 420 || code == 429) {
      return const GatewayError('Trop de requêtes. Réessayez dans quelques instants.', isFlood: true);
    }
    if (code >= 500) {
      return const GatewayError('Erreur Telegram. Réessayez plus tard.');
    }
    return GatewayError('Erreur Telegram${message.isEmpty ? '.' : ' : ${message.toLowerCase()}'}');
  }

  // ---------------------------------------------------------------------
  // API publique de la passerelle
  // ---------------------------------------------------------------------

  @override
  Future<void> requestPhone(String phone) async {
    await _request('setAuthenticationPhoneNumber', {'phone_number': phone});
  }

  @override
  Future<void> checkCode(String code) async {
    await _request('checkAuthenticationCode', {'code': code.trim()});
  }

  @override
  Future<void> checkPassword(String password) async {
    await _request('checkAuthenticationPassword', {'password': password});
  }

  @override
  Future<GatewayUser?> getMe() async {
    final Map<String, dynamic> me = await _request('getMe', {});
    if (me['@type'] != 'user') return null;
    return GatewayUser(
      firstName: me['first_name']?.toString() ?? '',
      lastName: me['last_name']?.toString(),
      username: me['username']?.toString(),
      phone: me['phone_number']?.toString(),
    );
  }

  @override
  Future<List<GatewayChat>> getChannels({int limit = 100}) async {
    final Map<String, dynamic> response = await _request('getChats', {
      'chat_list': {'@type': 'chatListMain'},
      'limit': limit,
    });
    final List<dynamic> ids = response['chat_ids'] as List<dynamic>? ?? const [];
    final List<GatewayChat> chats = [];
    for (final dynamic id in ids) {
      try {
        final Map<String, dynamic> chat = await _request('getChat', {'chat_id': id});
        final GatewayChat? converted = _chatFromTd(chat);
        if (converted != null && converted.id != null) chats.add(converted);
      } on GatewayError {
        continue; // une conversation inaccessible ne bloque pas les autres
      }
    }
    return chats;
  }

  @override
  Future<GatewayChat> resolveChannel(String input) async {
    final String trimmed = input.trim();
    String candidate = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;

    // Liens t.me : username ou invitation (t.me/+hash, t.me/joinchat/hash).
    if (candidate.contains('t.me')) {
      final String url = candidate.startsWith('http') ? candidate : 'https://$candidate';
      final Uri? uri = Uri.tryParse(url);
      final List<String> segments = uri?.pathSegments ?? const [];
      if (segments.isEmpty) {
        throw const GatewayError('Format de source invalide.');
      }
      if (segments.first.startsWith('+')) {
        return _resolveInvite(segments.first.substring(1));
      }
      if (segments.first == 'joinchat') {
        if (segments.length < 2) {
          throw const GatewayError('Format de source invalide.');
        }
        return _resolveInvite(segments[1]);
      }
      return _resolveUsername(segments.first);
    }

    return _resolveUsername(candidate);
  }

  Future<GatewayChat> _resolveUsername(String username) async {
    final Map<String, dynamic> chat = await _request('searchPublicChat', {'username': username});
    final GatewayChat? converted = _chatFromTd(chat);
    if (converted == null) {
      throw const GatewayError('Ce canal n\'est pas accessible avec ce compte Telegram.');
    }
    return converted;
  }

  Future<GatewayChat> _resolveInvite(String hash) async {
    final Map<String, dynamic> info = await _request('checkChatInviteLink', {'invite_link': hash});
    if (info['@type'] != 'chatInviteLinkInfo') {
      throw const GatewayError('Ce canal n\'est pas accessible avec ce compte Telegram.');
    }
    return GatewayChat(
      id: null,
      title: info['title']?.toString() ?? 'Canal privé',
      kind: GatewayChatKind.private,
      description: info['description']?.toString(),
      memberCount: (info['member_count'] as num?)?.toInt(),
      inviteHash: hash,
    );
  }

  GatewayChat? _chatFromTd(Map<String, dynamic> chat) {
    final Map<String, dynamic>? type = chat['type'] as Map<String, dynamic>?;
    final String typeName = type?['@type']?.toString() ?? '';
    final GatewayChatKind kind;
    if (typeName == 'chatTypeSupergroup') {
      kind = (type?['is_channel'] as bool?) == true ? GatewayChatKind.channel : GatewayChatKind.group;
    } else if (typeName == 'chatTypeBasicGroup') {
      kind = GatewayChatKind.group;
    } else {
      return null; // conversations privées/secretes : jamais proposées
    }
    return GatewayChat(
      id: (chat['id'] as num).toInt(),
      title: chat['title']?.toString() ?? '',
      username: chat['username']?.toString(),
      kind: kind,
    );
  }

  @override
  Future<List<GatewayMessage>> getMessages({
    required int chatId,
    int limit = 50,
    int? fromMessageId,
  }) async {
    final Map<String, dynamic> response = await _request('getChatHistory', {
      'chat_id': chatId,
      'from_message_id': fromMessageId ?? 0,
      'offset': 0,
      'limit': limit.clamp(1, 100),
      'only_local': false,
    });
    final List<dynamic> raw = response['messages'] as List<dynamic>? ?? const [];
    final List<GatewayMessage> messages = [];
    for (final dynamic item in raw) {
      final GatewayMessage? message = _messageFromTd(item as Map<String, dynamic>, chatId);
      if (message != null) messages.add(message);
    }
    return messages;
  }

  @override
  Future<GatewayMessage> getMessage({required int chatId, required int messageId}) async {
    final Map<String, dynamic> response = await _request('getMessage', {
      'chat_id': chatId,
      'message_id': messageId,
    });
    final GatewayMessage? message = _messageFromTd(response, chatId);
    if (message == null) {
      throw const GatewayError("Cette publication n'est pas un média exploitable.");
    }
    return message;
  }

  @override
  Future<GatewayFileSnapshot> getFileSnapshot(int fileId) async {
    final Map<String, dynamic> response = await _request('getFile', {'file_id': fileId});
    return GatewayFileSnapshot.fromTd(response);
  }

  @override
  Future<void> startDownload({
    required int fileId,
    required int offset,
    int limit = 0,
    bool priority = false,
  }) async {
    // La requête `downloadFile` (synchronisé = faux par défaut) revient
    // dès le lancement ; la progression arrive par `updateFile`. La réponse
    // finale (ou l'erreur d'annulation) est consommée silencieusement.
    unawaited(() async {
      try {
        await _request('downloadFile', {
          'file_id': fileId,
          'chunk_size': kDownloadChunkBytes,
          'offset': offset,
          'limit': limit,
          'priority': priority,
        });
      } on GatewayError {
        // Annulation ou interruption : le suivi (updateFile) s'arrête,
        // l'état est géré par le téléchargeur.
      }
    }());
  }

  @override
  Future<void> cancelDownload({required int fileId}) async {
    try {
      await _request('cancelDownloadFile', {'file_id': fileId, 'only_if_pending': false});
    } on GatewayError {
      // Le téléchargement a pu s'achever entre-temps : non bloquant.
    }
  }

  @override
  Future<void> deleteDownloadedFile({required int fileId}) async {
    try {
      await _request('deleteDownloadedFile', {'file_id': fileId});
    } on GatewayError {
      // Fichier déjà absent : non bloquant.
    }
  }

  /// Granularité des requêtes de téléchargement (multiple de 1024, comme
  /// l'exige TDLib pour [offset]).
  static const int kDownloadChunkBytes = 512 * 1024;

  GatewayMessage? _messageFromTd(Map<String, dynamic> message, int chatId) {
    final Map<String, dynamic>? content = message['content'] as Map<String, dynamic>?;
    final String contentType = content?['@type']?.toString() ?? '';
    final int messageId = (message['id'] as num).toInt();
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(
      (message['date'] as num).toInt() * 1000,
      isUtc: true,
    );

    String? text;
    String mediaType = 'unknown';
    String? fileName;
    int? fileSize;
    String? mimeType;
    int? duration;
    int? width;
    int? height;
    int? fileId;

    switch (contentType) {
      case 'messageText':
        text = (content?['text'] as Map<String, dynamic>?)?['text']?.toString();
        mediaType = 'text';
        break;
      case 'messageVideo':
        final Map<String, dynamic>? video = content?['video'] as Map<String, dynamic>?;
        mediaType = 'video';
        fileName = video?['file_name']?.toString();
        mimeType = video?['mime_type']?.toString();
        duration = (video?['duration'] as num?)?.toInt();
        width = (video?['width'] as num?)?.toInt();
        height = (video?['height'] as num?)?.toInt();
        fileSize = _expectedSize(video?['video'] as Map<String, dynamic>?);
        fileId = _fileId(video?['video'] as Map<String, dynamic>?);
        break;
      case 'messageAnimation':
        final Map<String, dynamic>? animation = content?['animation'] as Map<String, dynamic>?;
        mediaType = 'video';
        fileName = animation?['file_name']?.toString();
        mimeType = animation?['mime_type']?.toString();
        duration = (animation?['duration'] as num?)?.toInt();
        width = (animation?['width'] as num?)?.toInt();
        height = (animation?['height'] as num?)?.toInt();
        fileSize = _expectedSize(animation?['animation'] as Map<String, dynamic>?);
        fileId = _fileId(animation?['animation'] as Map<String, dynamic>?);
        break;
      case 'messageVideoNote':
        mediaType = 'video';
        duration = (content?['video_note'] as Map<String, dynamic>?)?['duration'] as int?;
        break;
      case 'messageDocument':
        final Map<String, dynamic>? document = content?['document'] as Map<String, dynamic>?;
        fileName = document?['file_name']?.toString();
        mimeType = document?['mime_type']?.toString();
        fileSize = _expectedSize(document?['document'] as Map<String, dynamic>?);
        fileId = _fileId(document?['document'] as Map<String, dynamic>?);
        mediaType = (mimeType?.startsWith('video/') ?? false)
            ? 'video'
            : (mimeType?.startsWith('audio/') ?? false)
                ? 'audio'
                : 'document';
        break;
      case 'messageAudio':
        final Map<String, dynamic>? audio = content?['audio'] as Map<String, dynamic>?;
        mediaType = 'audio';
        fileName = audio?['file_name']?.toString();
        mimeType = audio?['mime_type']?.toString();
        duration = (audio?['duration'] as num?)?.toInt();
        fileSize = _expectedSize(audio?['audio'] as Map<String, dynamic>?);
        fileId = _fileId(audio?['audio'] as Map<String, dynamic>?);
        break;
      case 'messagePhoto':
        mediaType = 'image';
        break;
      case 'messageSticker':
        mediaType = 'image';
        break;
      default:
        mediaType = 'text';
    }

    final String? caption = (message['caption'] as Map<String, dynamic>?)?['text']?.toString();
    if (text == null || text.isEmpty) text = caption;

    return GatewayMessage(
      messageId: messageId,
      chatId: chatId,
      date: date,
      text: text,
      mediaType: mediaType,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      duration: duration,
      width: width,
      height: height,
      messageLink: null, // le lien est construit par l'appelant (chat connu)
      fileId: fileId,
    );
  }

  int? _fileId(Map<String, dynamic>? file) {
    final int? id = (file?['id'] as num?)?.toInt();
    return id == null || id <= 0 ? null : id;
  }

  int? _expectedSize(Map<String, dynamic>? file) {
    final int? size = (file?['expected_size'] as num?)?.toInt();
    return size == null || size <= 0 ? null : size;
  }

  void _setState(GatewayAuthState state) {
    if (_authState == state) return;
    _authState = state;
    if (!_authController.isClosed) _authController.add(state);
  }
}
