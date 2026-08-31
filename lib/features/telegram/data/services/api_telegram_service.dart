import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/api_exception.dart';
import '../models/resolved_channel.dart';
import '../models/source_status.dart';
import '../models/sync_history_entry.dart';
import '../models/sync_progress.dart';
import '../models/sync_stats.dart';
import '../models/telegram_message.dart';
import '../models/telegram_source.dart';
import '../models/telegram_user.dart';
import 'telegram_service.dart';
import 'telegram_session_service.dart';

/// Service Telegram RÉEL : l'application dialogue avec le backend API,
/// qui porte seul les secrets Telegram (API_ID / API_HASH / session
/// serveur). Aucune donnée sensible ne transite vers l'application.
///
/// Architecture :  App ──HTTPS──► Backend API ──► Service Telegram ──► API Telegram
class ApiTelegramService extends ChangeNotifier implements TelegramService {
  ApiTelegramService({
    required String baseUrl,
    required TelegramSessionService session,
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        // ignore: prefer_initializing_formals
        _session = session,
        _client = client ?? http.Client() {
    // Au démarrage : restaurer la session sauvegardée (sécurisée) si elle existe.
    _restoreDone = _restore();
  }

  final String _baseUrl;
  final TelegramSessionService _session;
  final http.Client _client;

  /// Délai maximal des requêtes (injectable pour les tests).
  final Duration timeout;

  String? _token;
  TelegramUser? _currentUser;
  TelegramAuthState _authState = TelegramAuthState.disconnected;
  String? _authError;

  /// Terminé quand la restauration initiale de session est faite :
  /// toute requête attend ce futur pour porter le bon jeton d'accès.
  late final Future<void> _restoreDone;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  final List<TelegramSource> _sources = [];
  SyncStats _stats = const SyncStats(analyzedPosts: 0, detectedAnime: 0, detectedEpisodes: 0, duplicatesGrouped: 0, newEpisodes: 0);
  final List<SyncHistoryEntry> _history = [];
  bool _isSyncing = false;
  SyncProgress? _progress;

  @override
  bool get isBackendApi => true;

  /// URL du backend (affichée dans les réglages, sans secret).
  @override
  String? get apiBaseUrl => _baseUrl;

  // -------------------------------------------------------------------
  // Restauration de session (stockage sécurisé)
  // -------------------------------------------------------------------

  Future<void> _restore() async {
    final String? token = await _session.readToken();
    if (token == null || token.isEmpty) {
      // Aucune session sauvegardée : l'état par défaut (disconnected)
      // est déjà correct, on ne touche à rien.
      return;
    }
    _token = token;
    _authState = TelegramAuthState.connecting;
    final String? userJson = await _session.readUserJson();
    if (userJson != null) {
      try {
        _currentUser = TelegramUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      } on FormatException {
        _currentUser = null;
      }
    }
    _notify();
    // Vérification de la session auprès du backend (requête brute :
    // on est précisément en train de restaurer la session).
    try {
      final Map<String, dynamic> response =
          await _rawRequest('GET', '/api/telegram/status');
      final Map<String, dynamic>? user = response['user'] as Map<String, dynamic>?;
      if (user != null) _currentUser = TelegramUser.fromJson(user);
      _authState = TelegramAuthState.connected;
      _authError = null;
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.unauthorized) {
        _authState = TelegramAuthState.expired;
        await _session.clear();
        _token = null;
      } else {
        _authState = TelegramAuthState.error;
        _authError = error.displayMessage;
      }
    }
    _notify();
  }

  // -------------------------------------------------------------------
  // Authentification
  // -------------------------------------------------------------------

  @override
  TelegramAuthState get authState => _authState;

  @override
  TelegramUser? get currentUser => _currentUser;

  @override
  String? get authError => _authError;

  @override
  Future<void> requestCode(String phone) async {
    _authState = TelegramAuthState.connecting;
    _authError = null;
    _notify();
    await _request('POST', '/api/telegram/send-code', body: {'phone': phone});
  }

  @override
  Future<void> verifyCode(String phone, String code) async {
    final Map<String, dynamic> response =
        await _request('POST', '/api/telegram/verify-code', body: {'phone': phone, 'code': code});
    _token = response['token'] as String?;
    final Map<String, dynamic>? user = response['user'] as Map<String, dynamic>?;
    if (_token == null || user == null) {
      throw const ApiException(ApiErrorKind.server);
    }
    _currentUser = TelegramUser.fromJson(user);
    _authState = TelegramAuthState.connected;
    _authError = null;
    await _session.writeToken(_token!);
    await _session.writeUserJson(jsonEncode(user));
    _notify();
    unawaited(loadSources());
  }

  @override
  Future<void> disconnect() async {
    final String? token = _token;
    try {
      if (token != null) {
        await _request('POST', '/api/telegram/logout');
      }
    } on ApiException {
      // Même en cas d'erreur réseau, la session locale est effacée.
    } finally {
      _token = null;
      _currentUser = null;
      _authState = TelegramAuthState.disconnected;
      _authError = null;
      await _session.clear();
      _notify();
    }
  }

  @override
  Future<void> refreshSession() async {
    if (_token == null) {
      _authState = TelegramAuthState.disconnected;
      _notify();
      return;
    }
    try {
      final Map<String, dynamic> response = await _request('GET', '/api/telegram/status');
      final Map<String, dynamic>? user = response['user'] as Map<String, dynamic>?;
      if (user != null) _currentUser = TelegramUser.fromJson(user);
      _authState = TelegramAuthState.connected;
      _authError = null;
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.unauthorized) {
        // Jeton révoqué : session expirée.
        _authState = TelegramAuthState.expired;
        _authError = null;
        await _session.clear();
        _token = null;
      } else if (error.kind == ApiErrorKind.network || error.kind == ApiErrorKind.timeout) {
        _authState = TelegramAuthState.error;
        _authError = error.displayMessage;
      } else {
        _authState = TelegramAuthState.error;
        _authError = error.displayMessage;
      }
    }
    _notify();
  }

  // -------------------------------------------------------------------
  // Requêtes HTTP
  // -------------------------------------------------------------------

  Future<Map<String, dynamic>> _request(String method, String path, {Map<String, dynamic>? body}) async {
    // La session doit être restaurée avant d'émettre la requête.
    await _restoreDone;
    return _rawRequest(method, path, body: body);
  }

  /// Requête HTTP sans attente de restauration (utilisée uniquement par
  /// la restauration elle-même pour éviter une attente circulaire).
  Future<Map<String, dynamic>> _rawRequest(String method, String path, {Map<String, dynamic>? body}) async {
    final Uri uri = Uri.parse('$_baseUrl$path');
    final Map<String, String> headers = {'Content-Type': 'application/json'};
    if (_token != null) headers['Authorization'] = 'Bearer $_token';

    http.Response response;
    try {
      final http.Request request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final http.StreamedResponse streamed =
          await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(ApiErrorKind.timeout);
    } on http.ClientException {
      // Les SocketException sont enveloppées dans des ClientException
      // par package:http (compatible web).
      throw ApiException(ApiErrorKind.network);
    }

    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      decoded = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded ?? const {};
    }
    throw apiErrorFromResponse(response.statusCode, decoded);
  }

  // -------------------------------------------------------------------
  // Sources
  // -------------------------------------------------------------------

  @override
  List<TelegramSource> get sources => List.unmodifiable(_sources);

  @override
  TelegramSource? sourceById(String id) {
    for (final TelegramSource source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<void> loadSources() async {
    final Map<String, dynamic> response = await _request('GET', '/api/sources');
    final List<dynamic>? raw = response['sources'] as List<dynamic>?;
    _sources
      ..clear()
      ..addAll([
        for (final dynamic item in raw ?? const <dynamic>[])
          TelegramSource.fromJson(item as Map<String, dynamic>),
      ]);
    _notify();
  }

  @override
  Future<ResolvedChannel> resolveChannel(String input) async {
    final Map<String, dynamic> response =
        await _request('POST', '/api/sources/resolve', body: {'input': input});
    final Map<String, dynamic>? channel = response['channel'] as Map<String, dynamic>?;
    if (channel == null) throw const ApiException(ApiErrorKind.unknown);
    return ResolvedChannel.fromJson(channel);
  }

  @override
  Future<TelegramSource> addSource({required String name, required String username}) async {
    final Map<String, dynamic> response = await _request('POST', '/api/sources', body: {
      'input': username,
      if (name.isNotEmpty) 'name': name,
    });
    final Map<String, dynamic>? source = response['source'] as Map<String, dynamic>?;
    if (source == null) throw const ApiException(ApiErrorKind.unknown);
    final TelegramSource added = TelegramSource.fromJson(source);
    _sources.add(added);
    _notify();
    return added;
  }

  @override
  Future<void> removeSource(String sourceId) async {
    await _request('DELETE', '/api/sources/$sourceId');
    _sources.removeWhere((TelegramSource source) => source.id == sourceId);
    _notify();
  }

  @override
  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    final Map<String, dynamic> response = await _request('PATCH', '/api/sources/$sourceId',
        body: {'sync_enabled': enabled});
    final Map<String, dynamic>? source = response['source'] as Map<String, dynamic>?;
    if (source == null) return;
    final TelegramSource updated = TelegramSource.fromJson(source);
    final int index = _sources.indexWhere((TelegramSource s) => s.id == sourceId);
    if (index != -1) _sources[index] = updated;
    _notify();
  }

  // -------------------------------------------------------------------
  // Publications
  // -------------------------------------------------------------------

  @override
  Future<List<TelegramMessage>> fetchMessages(String sourceId, {int limit = 20}) async {
    final Map<String, dynamic> response =
        await _request('GET', '/api/sources/$sourceId/messages?limit=$limit');
    final List<dynamic>? raw = response['messages'] as List<dynamic>?;
    return [
      for (final dynamic item in raw ?? const <dynamic>[])
        TelegramMessage.fromJson(item as Map<String, dynamic>),
    ];
  }

  // -------------------------------------------------------------------
  // Statistiques & synchronisation
  // -------------------------------------------------------------------

  @override
  SyncStats get stats => _stats;

  @override
  bool get isSyncing => _isSyncing;

  @override
  SyncProgress? get currentProgress => _progress;

  @override
  List<SyncHistoryEntry> get history => List.unmodifiable(_history);

  @override
  Future<void> loadStats() async {
    final Map<String, dynamic> response = await _request('GET', '/api/stats');
    _applyStats(response);
    _notify();
  }

  void _applyStats(Map<String, dynamic> response) {
    final Map<String, dynamic>? raw = response['stats'] as Map<String, dynamic>?;
    if (raw != null) {
      _stats = SyncStats(
        analyzedPosts: (raw['analyzed_posts'] as num?)?.toInt() ?? 0,
        detectedAnime: (raw['detected_anime'] as num?)?.toInt() ?? 0,
        detectedEpisodes: (raw['detected_episodes'] as num?)?.toInt() ?? 0,
        duplicatesGrouped: (raw['duplicates_grouped'] as num?)?.toInt() ?? 0,
        newEpisodes: (raw['new_episodes'] as num?)?.toInt() ?? 0,
        lastSync: DateTime.tryParse((raw['last_sync'] as String?) ?? ''),
      );
    }
    final List<dynamic>? rawHistory = response['history'] as List<dynamic>?;
    if (rawHistory != null) {
      _history
        ..clear()
        ..addAll([
          for (final dynamic item in rawHistory)
            SyncHistoryEntry(
              id: ((item as Map<String, dynamic>)['id'] as String?) ?? '',
              date: DateTime.tryParse((item['date'] as String?) ?? '') ?? DateTime.now(),
              success: (item['success'] as bool?) ?? true,
              analyzedPosts: (item['analyzed_posts'] as num?)?.toInt() ?? 0,
              newEpisodes: (item['new_episodes'] as num?)?.toInt() ?? 0,
              errorMessage: item['error'] as String?,
            ),
        ]);
    }
  }

  @override
  Future<void> syncSource({String? sourceId}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    _progress = const SyncProgress(
      fraction: null, // progression indéterminée (requête backend)
      phase: 'Analyzing publications...',
      analyzedPosts: 0,
      totalPosts: 0,
    );
    _notify();
    try {
      final Map<String, dynamic> response = sourceId == null
          ? await _request('POST', '/api/sync')
          : await _request('POST', '/api/sources/$sourceId/sync');
      _applyStats(response);
      await loadSources();
    } on ApiException {
      rethrow;
    } finally {
      _isSyncing = false;
      _progress = null;
      _notify();
    }
  }

  @override
  Future<void> syncAll() => syncSource();

  @override
  SourceStatus? simulatedSourceStatus;

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
