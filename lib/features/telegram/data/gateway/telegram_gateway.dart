import 'dart:async';

/// États d'autorisation de la passerelle Telegram (miroir des états TDLib).
enum GatewayAuthState {
  /// Aucun client actif.
  notConnected,

  /// Client créé, paramètres en cours, connexion en cours.
  connecting,

  /// Telegram attend le code de connexion.
  codeRequired,

  /// Telegram attend le mot de passe 2FA.
  passwordRequired,

  /// Compte connecté et session valide.
  connected,

  /// La session enregistrée n'est plus valide (révoquée à distance).
  sessionExpired,

  /// Erreur bloquante (message dans [TelegramGateway.lastError]).
  error,
}

/// Profil public du compte connecté.
class GatewayUser {
  const GatewayUser({required this.firstName, this.lastName, this.username, this.phone});

  final String firstName;
  final String? lastName;
  final String? username;
  final String? phone;

  String get fullName => [firstName, lastName].whereType<String>().join(' ').trim();
}

/// Type de conversation Telegram.
enum GatewayChatKind { channel, group, private }

/// Aperçu d'un canal/groupe accessible.
class GatewayChat {
  const GatewayChat({
    required this.id,
    required this.title,
    this.username,
    this.kind = GatewayChatKind.channel,
    this.description,
    this.memberCount,
    this.inviteHash,
  });

  /// Identifiant numérique TDLib (null pour un lien d'invitation non rejoint).
  final int? id;
  final String title;
  final String? username;
  final GatewayChatKind kind;
  final String? description;
  final int? memberCount;

  /// Hash du lien d'invitation (t.me/+hash) — canal privé non rejoint.
  final String? inviteHash;

  /// Lien t.me public (null si le canal n'a pas de username).
  String? get telegramLink => username == null ? null : 'https://t.me/$username';
}

/// Une publication Telegram brute (références conservées, jamais inventées).
class GatewayMessage {
  const GatewayMessage({
    required this.messageId,
    required this.chatId,
    required this.date,
    this.text,
    required this.mediaType,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.duration,
    this.width,
    this.height,
    this.messageLink,
  });

  final int messageId;
  final int chatId;
  final DateTime date;
  final String? text;

  /// video | document | image | audio | text | unknown.
  final String mediaType;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final int? duration;
  final int? width;
  final int? height;

  /// Lien t.me vers la publication — null quand Telegram ne permet pas de
  /// construire un lien (jamais inventé).
  final String? messageLink;
}

/// Erreur de passerelle — toujours porteuse d'un message compréhensible.
class GatewayError implements Exception {
  const GatewayError(this.message, {this.code, this.isFlood = false});

  final String message;
  final int? code;
  final bool isFlood;

  @override
  String toString() => 'GatewayError($message)';
}

/// Lien t.me vers une publication — jamais inventé : null si Telegram ne
/// permet pas de construire un lien (pas de username, pas de canal privé).
String? telegramMessageLink({
  required int chatId,
  required int messageId,
  String? username,
  GatewayChatKind kind = GatewayChatKind.channel,
}) {
  if (username != null && username.isNotEmpty) {
    return 'https://t.me/$username/$messageId';
  }
  // Supergroupe/canal privé : t.me/c/<id>/<messageId>.
  if (kind != GatewayChatKind.group && chatId < -1000000000000) {
    final int channelId = -chatId - 1000000000000;
    return 'https://t.me/c/$channelId/$messageId';
  }
  return null;
}

/// Contrat de la couche Telegram réelle.
///
/// L'implémentation de production ([TdlibTelegramGateway]) s'appuie sur
/// TDLib — la bibliothèque officielle Telegram, embarquée sur Android.
/// Les tests utilisent une fausse passerelle ([FakeTelegramGateway]) qui
/// reproduit le même protocole, sans réseau.
///
/// Aucune donnée ne quitte l'appareil : la passerelle dialogue directement
/// avec les serveurs Telegram.
abstract class TelegramGateway {
  /// Crée le client et restaure la session enregistrée si elle existe.
  Future<void> connect();

  /// Ferme proprement le client (la session reste enregistrée).
  Future<void> close();

  /// Déconnecte le compte : la session est définitivement supprimée.
  Future<void> logout();

  /// Clé de chiffrement de la base de session (fournie par le gestionnaire
  /// de session ; sans effet pour les implémentations qui n'en ont pas).
  void setEncryptionKey(String key) {}

  /// État d'autorisation courant.
  GatewayAuthState get authState;

  /// Flux des changements d'état (écrans, service).
  Stream<GatewayAuthState> get authStates;

  /// Dernier message d'erreur compréhensible (jamais de secret).
  String? get lastError;

  /// Envoie le numéro de téléphone (format international).
  Future<void> requestPhone(String phone);

  /// Vérifie le code de connexion reçu via Telegram.
  Future<void> checkCode(String code);

  /// Vérifie le mot de passe 2FA (jamais contourné).
  Future<void> checkPassword(String password);

  /// Profil du compte connecté (null si non connecté).
  Future<GatewayUser?> getMe();

  /// Canaux/groupes accessibles par le compte.
  Future<List<GatewayChat>> getChannels({int limit = 100});

  /// Résout un identifiant (@username, t.me/username ou t.me/+hash).
  /// Lève une [GatewayError] « inaccessible » si le compte n'y a pas accès.
  Future<GatewayChat> resolveChannel(String input);

  /// Publications d'une conversation — PAGINÉE (jamais tout en mémoire).
  ///
  /// [fromMessageId] = null : les plus récentes d'abord ;
  /// sinon la page suivante (messages antérieurs à cet identifiant).
  Future<List<GatewayMessage>> getMessages({
    required int chatId,
    int limit = 50,
    int? fromMessageId,
  });
}
