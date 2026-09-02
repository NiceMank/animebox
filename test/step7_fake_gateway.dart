import 'dart:async';

import 'package:animebox/features/telegram/data/gateway/telegram_gateway.dart';

/// Fausse passerelle Telegram pour les tests — reproduit le protocole de
/// [TelegramGateway] sans réseau : connexion (code / 2FA), résolution de
/// canaux (accessibles/inaccessibles), récupération paginée de messages.
class FakeTelegramGateway implements TelegramGateway {
  FakeTelegramGateway({
    this.requirePassword = false,
    this.autoConnectOnCreate = false,
    List<GatewayChat>? channels,
    Map<int, List<GatewayMessage>>? messages,
    this.failOnNextFetch,
    this.delayPerFetch = Duration.zero,
  })  : channels = channels ?? [],
        messages = messages ?? {};

  /// Si vrai, `checkCode` bascule en `passwordRequired` (compte 2FA).
  bool requirePassword;

  /// Si vrai, la session est déjà valide à la création (restauration).
  bool autoConnectOnCreate;

  /// Canaux résolubles.
  final List<GatewayChat> channels;

  /// Messages par chatId (identifiants croissants).
  final Map<int, List<GatewayMessage>> messages;

  /// Erreur à lever lors de la prochaine récupération (réseau, etc.).
  GatewayError? failOnNextFetch;

  /// Délai artificiel par page (tests d'annulation).
  Duration delayPerFetch;

  GatewayAuthState _state = GatewayAuthState.notConnected;
  final StreamController<GatewayAuthState> _states = StreamController<GatewayAuthState>.broadcast();
  final StreamController<GatewayFileSnapshot> _fileUpdates =
      StreamController<GatewayFileSnapshot>.broadcast();

  final List<String> callLog = [];

  @override
  GatewayAuthState get authState => _state;

  @override
  Stream<GatewayAuthState> get authStates => _states.stream;

  @override
  String? get lastError => null;

  @override
  Future<void> connect() async {
    callLog.add('connect');
    if (autoConnectOnCreate) {
      _set(GatewayAuthState.connected);
    } else {
      _set(GatewayAuthState.notConnected);
    }
  }

  @override
  Future<void> close() async {
    callLog.add('close');
    _set(GatewayAuthState.notConnected);
  }

  @override
  Future<void> logout() async {
    callLog.add('logout');
    _set(GatewayAuthState.notConnected);
  }

  @override
  void setEncryptionKey(String key) {
    callLog.add('setEncryptionKey');
  }

  @override
  Future<void> requestPhone(String phone) async {
    callLog.add('requestPhone');
    _set(GatewayAuthState.codeRequired);
  }

  @override
  Future<void> checkCode(String code) async {
    callLog.add('checkCode');
    if (code != '12345') {
      throw const GatewayError('Code de connexion incorrect.');
    }
    _set(requirePassword ? GatewayAuthState.passwordRequired : GatewayAuthState.connected);
  }

  @override
  Future<void> checkPassword(String password) async {
    callLog.add('checkPassword');
    if (password != 'motdepasse2fa') {
      throw const GatewayError('Mot de passe 2FA incorrect.');
    }
    _set(GatewayAuthState.connected);
  }

  @override
  Future<GatewayUser?> getMe() async {
    if (_state != GatewayAuthState.connected) return null;
    return const GatewayUser(firstName: 'Test', lastName: 'AnimeBox', username: 'test_user');
  }

  @override
  Future<List<GatewayChat>> getChannels({int limit = 100}) async {
    callLog.add('getChannels');
    return channels;
  }

  @override
  Future<GatewayChat> resolveChannel(String input) async {
    callLog.add('resolveChannel:$input');
    for (final GatewayChat chat in channels) {
      if (chat.username == input) return chat;
    }
    throw const GatewayError('Ce canal n\'est pas accessible avec ce compte Telegram.', code: 403);
  }

  @override
  Future<List<GatewayMessage>> getMessages({
    required int chatId,
    int limit = 50,
    int? fromMessageId,
  }) async {
    callLog.add('getMessages:$chatId:$fromMessageId');
    final GatewayError? failure = failOnNextFetch;
    if (failure != null) {
      failOnNextFetch = null;
      throw failure;
    }
    if (delayPerFetch > Duration.zero) {
      await Future<void>.delayed(delayPerFetch);
    }
    final List<GatewayMessage> all = messages[chatId] ?? const [];
    final List<GatewayMessage> sorted = List.of(all)
      ..sort((GatewayMessage a, GatewayMessage b) => b.messageId.compareTo(a.messageId));
    final List<GatewayMessage> filtered = fromMessageId == null
        ? sorted
        : sorted.where((GatewayMessage m) => m.messageId < fromMessageId).toList();
    return filtered.take(limit).toList();
  }

  // -------------------------------------------------------------------------
  // Médias (prompt 8) — simulation contrôlée du protocole TDLib.
  // -------------------------------------------------------------------------

  @override
  Future<GatewayMessage> getMessage({required int chatId, required int messageId}) async {
    callLog.add('getMessage:$chatId:$messageId');
    final GatewayError? failure = failOnNextFetch;
    if (failure != null) {
      failOnNextFetch = null;
      throw failure;
    }
    final List<GatewayMessage> all = messages[chatId] ?? const [];
    for (final GatewayMessage message in all) {
      if (message.messageId == messageId) return message;
    }
    throw const GatewayError('Publication introuvable.');
  }

  @override
  Future<GatewayFileSnapshot> getFileSnapshot(int fileId) async {
    final GatewayFileSnapshot? snapshot = files[fileId];
    if (snapshot == null) {
      throw const GatewayError('Fichier inconnu.');
    }
    return snapshot;
  }

  @override
  Stream<GatewayFileSnapshot> get fileUpdates => _fileUpdates.stream;

  @override
  Future<void> startDownload({
    required int fileId,
    required int offset,
    int limit = 0,
    bool priority = false,
  }) async {
    callLog.add('startDownload:$fileId:$offset');
    // Le test pilote la progression via [emitFileUpdate].
  }

  @override
  Future<void> cancelDownload({required int fileId}) async {
    callLog.add('cancelDownload:$fileId');
  }

  @override
  Future<void> deleteDownloadedFile({required int fileId}) async {
    callLog.add('deleteDownloadedFile:$fileId');
  }

  /// États de fichiers simulés (fileId → instantané).
  final Map<int, GatewayFileSnapshot> files = {};

  /// Publie une mise à jour de fichier (progression/complétion simulée).
  void emitFileUpdate(GatewayFileSnapshot snapshot) {
    files[snapshot.fileId] = snapshot;
    _fileUpdates.add(snapshot);
  }

  /// Simule la révocation distante de la session.
  void expireSession() => _set(GatewayAuthState.sessionExpired);

  void _set(GatewayAuthState state) {
    _state = state;
    _states.add(state);
  }

  Future<void> dispose() async {
    await _states.close();
    await _fileUpdates.close();
  }
}
