/// Modèles du téléchargeur (prompt 8) : états, requêtes, instantanés.
library;

/// État d'un téléchargement (règle 8 — aucun état intermédiaire inventé).
enum DownloadStatus { queued, downloading, paused, completed, failed, cancelled }

/// Type d'événement diffusé par le téléchargeur (base des futures
/// notifications — règle 34 — sans les implémenter maintenant).
enum DownloadEventKind { started, progress, paused, resumed, completed, failed, cancelled, deleted }

/// Demande de téléchargement — toutes les valeurs viennent du catalogue
/// réel (versions/épisodes/saisons) : aucune n'est inventée.
class DownloadRequest {
  const DownloadRequest({
    required this.versionId,
    required this.animeId,
    required this.seasonId,
    required this.episodeId,
    required this.animeTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    this.chatId,
    this.messageId,
    this.fileId,
    this.channelUsername,
    this.messageLink,
    this.qualityLabel,
    this.language,
    this.expectedSize,
    this.fileName,
  });

  final String versionId;
  final String animeId;
  final String seasonId;
  final String episodeId;

  /// Contexte de nommage des fichiers (noms réels, nettoyés).
  final String animeTitle;
  final int seasonNumber;
  final int episodeNumber;

  // ---- Références Telegram ----
  final int? chatId;
  final int? messageId;
  final int? fileId;
  final String? channelUsername;
  final String? messageLink;

  final String? qualityLabel;
  final String? language;

  /// Taille mesurée par la synchronisation (null si inconnue).
  final int? expectedSize;

  /// Nom de fichier d'origine (extension réelle).
  final String? fileName;

  /// Une référence Telegram exploitable existe-t-elle (règle 28) ?
  bool get hasTelegramReference => chatId != null && messageId != null;
}

/// Instantané immuable d'un téléchargement — affiché tel quel par l'UI.
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.versionId,
    required this.animeId,
    required this.seasonId,
    required this.episodeId,
    required this.animeTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.chatId,
    this.messageId,
    this.fileId,
    this.channelUsername,
    this.messageLink,
    this.qualityLabel,
    this.language,
    this.expectedSize,
    this.downloadedBytes = 0,
    this.localPath,
    this.fileName,
    this.error,
    this.resumable = true,
    this.speedBytesPerSec,
    this.eta,
  });

  final String id;
  final String versionId;
  final String animeId;
  final String seasonId;
  final String episodeId;
  final String animeTitle;
  final int seasonNumber;
  final int episodeNumber;

  final DownloadStatus status;

  /// Horodatages réels (création / dernière mise à jour persistée).
  final DateTime createdAt;
  final DateTime updatedAt;

  final int? chatId;
  final int? messageId;
  final int? fileId;
  final String? channelUsername;

  /// Lien t.me réel de la publication (conservé pour l'action Telegram).
  final String? messageLink;

  final String? qualityLabel;
  final String? language;

  /// Taille totale si connue (jamais inventée).
  final int? expectedSize;

  /// Octets réellement reçus (source : TDLib updateFile).
  final int downloadedBytes;

  /// Chemin du fichier TERMINÉ (null tant que non terminé).
  final String? localPath;

  /// Nom de fichier d'origine (extension réelle).
  final String? fileName;

  /// Message d'erreur compréhensible (états failed/cancelled).
  final String? error;

  /// Un échec/une interruption peut-il être repris (données locales OK) ?
  final bool resumable;

  // ---- Dérivés calculés depuis les valeurs RÉELLES ----

  /// Vitesse mesurée sur les dernières secondes (null si non mesurable).
  final double? speedBytesPerSec;

  /// Temps restant estimé (null si vitesse ou taille inconnue).
  final Duration? eta;

  String? get errorLabel => error;

  /// Fraction réelle (0..1) — null si la taille totale est inconnue.
  double? get fraction {
    final int? total = expectedSize;
    if (total == null || total <= 0) return null;
    return (downloadedBytes / total).clamp(0.0, 1.0);
  }

  bool get isActive => status == DownloadStatus.queued || status == DownloadStatus.downloading;

  bool get isBusy => status == DownloadStatus.downloading;

  DownloadTask copyWith({
    DownloadStatus? status,
    int? fileId,
    int? expectedSize,
    int? downloadedBytes,
    String? localPath,
    String? error,
    bool? resumable,
    double? speedBytesPerSec,
    Duration? eta,
    DateTime? updatedAt,
    bool clearError = false,
  }) =>
      DownloadTask(
        id: id,
        versionId: versionId,
        animeId: animeId,
        seasonId: seasonId,
        episodeId: episodeId,
        animeTitle: animeTitle,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        chatId: chatId,
        messageId: messageId,
        fileId: fileId ?? this.fileId,
        channelUsername: channelUsername,
        messageLink: messageLink,
        qualityLabel: qualityLabel,
        language: language,
        expectedSize: expectedSize ?? this.expectedSize,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        localPath: localPath ?? this.localPath,
        fileName: fileName,
        error: clearError ? null : (error ?? this.error),
        resumable: resumable ?? this.resumable,
        speedBytesPerSec: speedBytesPerSec,
        eta: eta,
      );
}

/// Événement du téléchargeur (flux brut — les notifications viendront plus
/// tard se brancher ici, règle 34).
class DownloadEvent {
  const DownloadEvent(this.kind, this.task);

  final DownloadEventKind kind;
  final DownloadTask task;
}
