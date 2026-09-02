/// Modèles du bloc média (prompt 8) : références Telegram d'une version,
/// informations média réelles et erreurs d'accès compréhensibles.
library;

/// Références Telegram conservées pour une version d'épisode.
///
/// Toutes les valeurs proviennent du catalogue (jamais inventées) : ce sont
/// elles qui permettent téléchargement, lecture et ouverture dans Telegram.
class VersionMediaRef {
  const VersionMediaRef({
    required this.versionId,
    this.chatId,
    this.messageId,
    this.fileId,
    this.channelUsername,
    this.messageLink,
    this.fileName,
    this.expectedSize,
    this.language,
    this.qualityLabel,
  });

  final String versionId;
  final int? chatId;
  final int? messageId;

  /// Identifiant TDLib du fichier — peut manquer (version ancienne) :
  /// il est alors résolu à la demande via `getMessage`, jamais inventé.
  final int? fileId;

  final String? channelUsername;

  /// Lien t.me réel de la publication (null si non constructible).
  final String? messageLink;

  final String? fileName;

  /// Taille annoncée par le catalogue (mesurée par TDLib à la synchro).
  final int? expectedSize;

  /// Langue détectée (VF, VOSTFR…) — « Langue inconnue » si absente.
  final String? language;

  /// Qualité normalisée (« 1080p »…) ou null.
  final String? qualityLabel;

  /// Une référence Telegram exploitable existe-t-elle ?
  bool get hasTelegramReference => chatId != null && messageId != null;

  /// Le lien t.me est-il directement ouvrable ?
  bool get hasTelegramLink => messageLink != null && messageLink!.isNotEmpty;
}

/// Informations média réelles, obtenues de Telegram (getMessage/getFile).
class MediaInfo {
  const MediaInfo({
    required this.fileId,
    this.expectedSize,
    this.mimeType,
    this.fileName,
    this.durationSec,
    this.isVideo = true,
  });

  final int fileId;
  final int? expectedSize;
  final String? mimeType;
  final String? fileName;
  final int? durationSec;
  final bool isVideo;
}

/// Raison d'une impossibilité d'accès (messages règles 29/30/31).
enum MediaAccessFailure {
  /// La publication a été supprimée sur Telegram.
  deleted,

  /// Le compte connecté n'a plus accès au contenu.
  inaccessible,

  /// Session Telegram absente ou expirée.
  sessionExpired,

  /// Réseau indisponible ou délai dépassé.
  offline,

  /// Aucune référence Telegram exploitable pour cette version.
  missingReference,

  /// Autre erreur (message compréhensible porté par l'exception).
  generic,
}

/// Erreur d'accès média — toujours porteuse d'un message compréhensible.
class MediaAccessException implements Exception {
  const MediaAccessException(this.kind, this.message);

  const MediaAccessException.deleted([String? detail])
      : this(MediaAccessFailure.deleted, detail ?? 'Ce média n\'est plus disponible sur Telegram.');

  const MediaAccessException.inaccessible([String? detail])
      : this(
          MediaAccessFailure.inaccessible,
          detail ?? "Cette publication n'est plus accessible avec le compte Telegram connecté.",
        );

  const MediaAccessException.sessionExpired([String? detail])
      : this(MediaAccessFailure.sessionExpired, detail ?? 'Session Telegram expirée. Reconnectez-vous depuis le profil.');

  const MediaAccessException.offline([String? detail])
      : this(MediaAccessFailure.offline, detail ?? 'Connexion Internet indisponible. Réessayez plus tard.');

  const MediaAccessException.missingReference()
      : this(MediaAccessFailure.missingReference, 'Aucune référence Telegram exploitable pour cette version.');

  const MediaAccessException.generic(String detail) : this(MediaAccessFailure.generic, detail);

  final MediaAccessFailure kind;
  final String message;

  @override
  String toString() => 'MediaAccessException($kind, $message)';

  /// Traduit une [GatewayError] TDLib en erreur média compréhensible.
  static MediaAccessException fromGateway(Object error) {
    final String text = error.toString();
    if (text.contains('Client Telegram non démarré') || text.contains('fermé')) {
      return const MediaAccessException.sessionExpired();
    }
    if (text.contains('trop de temps')) {
      return const MediaAccessException.offline();
    }
    if (text.contains('MESSAGE_ID_INVALID') ||
        text.contains('MESSAGE_DELETED') ||
        text.contains('CHAT_ID_INVALID')) {
      return const MediaAccessException.deleted();
    }
    if (text.contains('CHANNEL_PRIVATE') ||
        text.contains("n'est pas accessible")) {
      return const MediaAccessException.inaccessible();
    }
    if (error is Exception) {
      return MediaAccessException.generic(
        'Le média est momentanément indisponible. Réessayez plus tard.',
      );
    }
    return MediaAccessException.generic(
      'Le média est momentanément indisponible. Réessayez plus tard.',
    );
  }
}
