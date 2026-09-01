import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage clé/valeur sécurisé — implémentation de production :
/// Keystore/EncryptedSharedPreferences Android ; mémoire pour les tests.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Implémentation sur le stockage sécurisé natif.
class PlatformSecureStore implements SecureKeyValueStore {
  PlatformSecureStore()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Stockage en mémoire (tests) — même contrat.
class InMemoryKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Gestionnaire de session Telegram.
///
/// Responsabilités :
/// - conserver la CLÉ de chiffrement de la base TDLib (la session
///   Telegram elle-même vit dans le stockage chiffré de TDLib, espace
///   privé de l'application — jamais de fichier texte non chiffré) ;
/// - mémoriser le numéro utilisé et l'état de connexion ;
/// - restaurer la session au lancement et vérifier sa validité ;
/// - nettoyer après déconnexion.
///
/// Aucun secret n'est journalisé ni affiché.
class TelegramSessionManager {
  TelegramSessionManager({SecureKeyValueStore? store})
      : _store = store ?? PlatformSecureStore();

  final SecureKeyValueStore _store;

  static const String _keyDbEncryption = 'animebox_tdlib_db_key';
  static const String _keyPhone = 'animebox_tdlib_phone';
  static const String _keyWasConnected = 'animebox_tdlib_was_connected';

  final Random _random = Random.secure();

  /// Clé de chiffrement de la base TDLib — générée une fois puis
  /// conservée dans le stockage sécurisé.
  Future<String> ensureEncryptionKey() async {
    final String? existing = await _store.read(_keyDbEncryption);
    if (existing != null && existing.length >= 32) return existing;
    final String generated = _generateHex(32);
    await _store.write(_keyDbEncryption, generated);
    return generated;
  }

  Future<String?> readEncryptionKey() => _store.read(_keyDbEncryption);

  String _generateHex(int bytes) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < bytes; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Numéro utilisé lors de la dernière connexion (pré-rempli, jamais
  /// affiché en entier ailleurs que dans le champ).
  Future<String?> readPhone() => _store.read(_keyPhone);

  Future<void> savePhone(String phone) => _store.write(_keyPhone, phone);

  /// Marque qu'une session valide existait (détection d'expiration).
  Future<bool> wasConnected() async =>
      (await _store.read(_keyWasConnected)) == '1';

  Future<void> markConnected(bool connected) =>
      _store.write(_keyWasConnected, connected ? '1' : '0');

  /// Efface tout ce qui concerne la session (déconnexion).
  Future<void> clearSession() async {
    await _store.delete(_keyPhone);
    await _store.delete(_keyWasConnected);
    // La clé de chiffrement n'est PAS supprimée : la base TDLib (détruite
    // par logOut) reste inutilisable sans elle, et on évite de générer
    // une nouvelle clé incompatible avec un ancien fichier résiduel.
  }
}
