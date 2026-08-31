import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'telegram_session_service.dart';

/// Session stockée dans le stockage sécurisé de la plateforme
/// (Keystore/EncryptedSharedPreferences sur Android). Rien en clair
/// dans les préférences classiques.
class SecureSessionService implements TelegramSessionService {
  SecureSessionService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _storage;

  static const String _tokenKey = 'animebox_session_token';
  static const String _userKey = 'animebox_session_user';

  @override
  Future<String?> readToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> writeToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }

  @override
  Future<String?> readUserJson() async {
    try {
      return await _storage.read(key: _userKey);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> writeUserJson(String json) async {
    await _storage.write(key: _userKey, value: json);
  }
}

/// Session en mémoire : utilisée sur le web (démo) et dans les tests,
/// où le stockage sécurisé natif n'est pas disponible.
class InMemorySessionService implements TelegramSessionService {
  String? _token;
  String? _userJson;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> clear() async {
    _token = null;
    _userJson = null;
  }

  @override
  Future<String?> readUserJson() async => _userJson;

  @override
  Future<void> writeUserJson(String json) async => _userJson = json;
}
