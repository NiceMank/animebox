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
    this.fileId,
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

  /// Identifiant TDLib du fichier média (null si la publication n'en a pas).
  /// Nécessaire au téléchargement/à la lecture via TDLib — jamais inventé.
  final int? fileId;
}

/// État instantané d'un fichier TDLib (téléchargement ou cache local).
///
/// Toutes les valeurs proviennent de `getFile`/`updateFile` : aucune
/// progression n'est estimée ni simulée.
class GatewayFileSnapshot {
  const GatewayFileSnapshot({
    required this.fileId,
    this.expectedBytes,
    this.receivedBytes = 0,
    this.prefixBytes = 0,
    this.localPath,
    this.isDownloadCompleted = false,
    this.canBeDownloaded = true,
  });

  final int fileId;

  /// Taille totale si Telegram l'expose (sinon null — jamais inventée).
  final int? expectedBytes;

  /// Octets déjà présents localement (fichier partiel compris).
  final int receivedBytes;

  /// Octets contigus disponibles en tête de fichier (lecture progressive).
  final int prefixBytes;

  /// Chemin local du fichier (partiel ou complet) — null si absent.
  final String? localPath;

  /// Le fichier est-il entièrement téléchargé ?
  final bool isDownloadCompleted;

  /// TDLib autorise-t-il le téléchargement (fichier non restreint) ?
  final bool canBeDownloaded;

  static GatewayFileSnapshot fromTd(Map<String, dynamic> file) {
    final Map<String, dynamic> local = (file['local'] as Map<String, dynamic>?) ?? const {};
    final int? expected = (file['expected_size'] as num?)?.toInt() ??
        (file['size'] as num?)?.toInt();
    return GatewayFileSnapshot(
      fileId: (file['id'] as num).toInt(),
      expectedBytes: expected != null && expected > 0 ? expected : null,
      receivedBytes: ((local['downloaded_size'] ?? local['total_downloaded_size']) as num?)?.toInt() ?? 0,
      prefixBytes: (local['downloaded_prefix_size'] as num?)?.toInt() ?? 0,
      localPath: (local['path'] as String?)?.isEmpty == true ? null : local['path']?.toString(),
      isDownloadCompleted: (local['is_downloading_completed'] as bool?) ?? false,
      canBeDownloaded: (local['can_be_downloaded'] as bool?) ?? true,
    );
  }
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

  // -------------------------------------------------------------------------
  // Médias (prompt 8) — téléchargement et lecture via TDLib, en direct.
  // -------------------------------------------------------------------------

  /// Récupère UNE publication (vérification d'accessibilité réelle).
  ///
  /// Lève une [GatewayError] compréhensible si la publication a été
  /// supprimée ou n'est plus accessible avec le compte connecté.
  Future<GatewayMessage> getMessage({required int chatId, required int messageId});

  /// État actuel d'un fichier TDLib (progrès, chemin local, complétion).
  Future<GatewayFileSnapshot> getFileSnapshot(int fileId);

  /// Flux des mises à jour de fichiers TDLib (`updateFile`) — progression
  /// RÉELLE des téléchargements. Diffusé à tous les abonnés.
  Stream<GatewayFileSnapshot> get fileUpdates;

  /// Lance (ou poursuit) un téléchargement TDLib.
  ///
  /// [offset] doit être un multiple de 1024 (contrainte TDLib) ; la requête
  /// revient aussitôt, la progression arrive via [fileUpdates]. Ne lève
  /// qu'en cas de refus immédiat (fichier inaccessible…).
  Future<void> startDownload({
    required int fileId,
    required int offset,
    int limit = 0,
    bool priority = false,
  });

  /// Arrête un téléchargement en cours (le fichier partiel est conservé
  /// par TDLib : la reprise à l'offset correspondante reste possible).
  Future<void> cancelDownload({required int fileId});

  /// Supprime la copie locale TDLib d'un fichier COMPLET (après copie vers
  /// le stockage organisé d'AnimeBox) pour libérer l'espace.
  Future<void> deleteDownloadedFile({required int fileId});
}
