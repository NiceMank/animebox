import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../../anime/data/models/anime.dart';
import '../../anime/data/models/episode.dart';
import '../../anime/data/models/episode_quality.dart';
import '../../anime/data/models/season.dart';
import '../../anime/data/models/video_quality.dart';
import '../../telegram/data/gateway/telegram_gateway.dart';
import '../../anime/data/repositories/anime_repository.dart';
import '../models/download_models.dart';
import '../models/media_access.dart';
import 'download_manager.dart';

/// Décision de lecture RÉELLE pour une version (aucune simulation).
enum PlaybackKind {
  /// Fichier téléchargé complet, présent sur l'appareil → lecture hors ligne.
  localFile,

  /// Lecture depuis le téléchargement TDLib en cours (partiel contigu) —
  /// le lecteur suivra la progression et basculera sur le fichier final.
  partialStream,

  /// Lecture directe impossible → [ Ouvrir dans Telegram ].
  telegramFallback,

  /// Aucun accès possible (média supprimé, inaccessible, sans référence).
  unavailable,
}

/// Plan de lecture produit par [MediaService.preparePlayback].
class PlaybackPlan {
  const PlaybackPlan({
    required this.kind,
    this.localPath,
    this.expectedBytes,
    this.fileId,
    this.version,
    this.failure,
    this.message,
  });

  final PlaybackKind kind;

  /// Identifiant TDLib du fichier (suivi du téléchargement de lecture).
  final int? fileId;

  /// Chemin réel du fichier (complet ou partiel TDLib).
  final String? localPath;

  /// Taille totale si connue (barre de progression honnête).
  final int? expectedBytes;

  /// Version concernée (pour suivre le téléchargement en cours).
  final EpisodeQuality? version;

  /// Raison d'indisponibilité (kind = unavailable).
  final MediaAccessException? failure;

  /// Message optionnel affiché tel quel.
  final String? message;

  /// Le lien t.me réel de la publication (fallback).
  String? telegramLinkOf() => version?.telegramMessageLink;
}

/// Décision de la qualité par défaut pour un épisode (règle 6) :
/// Auto → meilleure qualité réellement disponible ; sinon la qualité
/// demandée si elle existe, sinon la meilleure (jamais de sélection vide).
EpisodeQuality selectPreferredQuality(
  Episode episode,
  QualityPreference preference,
) {
  final List<EpisodeQuality> available = episode.availableQualities;
  if (available.isEmpty) {
    final List<EpisodeQuality> sorted = episode.sortedQualities;
    return sorted.isEmpty ? episode.qualities.first : sorted.first;
  }
  if (preference == QualityPreference.auto) {
    return episode.sortedQualities.first;
  }
  final VideoQuality? target = preference.target;
  if (target != null) {
    for (final EpisodeQuality quality in available) {
      if (quality.quality == target) return quality;
    }
  }
  return episode.sortedQualities.first;
}

/// Couche média (prompt 8) — la seule à parler à Telegram et au
/// [DownloadManager] ; les widgets n'appellent que celle-ci.
///
/// Architecture : UI → (contrôleurs d'écran) → [MediaService] →
/// [TelegramGateway] / [DownloadManager] → TDLib → Telegram.
class MediaService {
  MediaService({
    required this.repository,
    required this.downloadManager,
    this.gateway,
  });

  final AnimeRepository repository;
  final DownloadManager downloadManager;

  /// Passerelle Telegram réelle (null en démonstration : aucune action
  /// réseau n'est alors possible — l'interface l'indique honnêtement).
  final TelegramGateway? gateway;

  bool get canAccessTelegram => gateway != null;

  // -------------------------------------------------------------------------
  // Informations média réelles (règle 1/2)
  // -------------------------------------------------------------------------

  /// Vérifie l'accessibilité RÉELLE d'une publication et renvoie les
  /// informations du média. Lève [MediaAccessException] en cas d'impossibilité
  /// (supprimé, inaccessible, session expirée, hors ligne…).
  Future<MediaInfo> resolveMedia({
    required int? chatId,
    required int? messageId,
    required int? fileId,
  }) async {
    final TelegramGateway? gw = gateway;
    if (gw == null) {
      throw const MediaAccessException.sessionExpired(
        'Connectez-vous à Telegram depuis le profil pour lire ou télécharger.',
      );
    }
    if (chatId == null || messageId == null) {
      throw const MediaAccessException.missingReference();
    }
    int resolvedFileId = fileId ?? 0;
    int? size;
    String? mimeType;
    String? fileName;
    int? durationSec;
    try {
      if (resolvedFileId <= 0) {
        final GatewayMessage message =
            await gw.getMessage(chatId: chatId, messageId: messageId);
        resolvedFileId = message.fileId ?? 0;
        size = message.fileSize;
        mimeType = message.mimeType;
        fileName = message.fileName;
        durationSec = message.duration;
        if (resolvedFileId <= 0) {
          throw const MediaAccessException.deleted();
        }
      } else {
        final GatewayFileSnapshot snapshot = await gw.getFileSnapshot(resolvedFileId);
        size = snapshot.expectedBytes;
      }
    } on GatewayError catch (error) {
      throw MediaAccessException.fromGateway(error);
    }
    return MediaInfo(
      fileId: resolvedFileId,
      expectedSize: size,
      mimeType: mimeType,
      fileName: fileName,
      durationSec: durationSec,
    );
  }

  // -------------------------------------------------------------------------
  // Préparation de lecture (règles 2/3/4)
  // -------------------------------------------------------------------------

  /// Construit le plan de lecture d'une version :
  /// 1. fichier téléchargé présent → lecture locale (hors connexion) ;
  /// 2. cache TDLib complet → lecture directe de ce fichier ;
  /// 3. média téléchargeable → lecture sur téléchargement en cours ;
  /// 4. sinon → « Lecture directe indisponible » + Ouvrir dans Telegram.
  Future<PlaybackPlan> preparePlayback({
    required Anime anime,
    required Episode episode,
    required EpisodeQuality version,
  }) async {
    // 1. Fichier local organisé déjà téléchargé ?
    final DownloadTask? download = downloadManager.taskForVersion(version.id);
    if (download != null && download.status == DownloadStatus.completed) {
      final String? path = download.localPath;
      if (path != null && File(path).existsSync()) {
        return PlaybackPlan(
          kind: PlaybackKind.localFile,
          localPath: path,
          expectedBytes: download.expectedSize,
          version: version,
        );
      }
    }

    // Sans Telegram réel : fallback honnête (lien réel ou indisponible).
    if (!canAccessTelegram) {
      if (version.hasTelegramLink) {
        return PlaybackPlan(
          kind: PlaybackKind.telegramFallback,
          version: version,
          message: 'Lecture directe indisponible. Ouvrez la publication dans Telegram.',
        );
      }
      return PlaybackPlan(
        kind: PlaybackKind.unavailable,
        version: version,
        failure: const MediaAccessException.sessionExpired(
          'Connectez-vous à Telegram depuis le profil pour lire cet épisode.',
        ),
      );
    }

    try {
      final MediaInfo info = await resolveMedia(
        chatId: version.sourceChannelId != null ? int.tryParse(version.sourceChannelId!) : null,
        messageId: version.telegramMessageId,
        fileId: null,
      );

      // 2. Cache TDLib déjà complet ?
      final GatewayFileSnapshot snapshot = await gateway!.getFileSnapshot(info.fileId);
      if (snapshot.isDownloadCompleted && snapshot.localPath != null) {
        return PlaybackPlan(
          kind: PlaybackKind.localFile,
          localPath: snapshot.localPath,
          expectedBytes: snapshot.expectedBytes,
          version: version,
        );
      }
      if (!snapshot.canBeDownloaded) {
        // TDLib refuse explicitement ce fichier (contenu restreint).
        if (version.hasTelegramLink) {
          return PlaybackPlan(
            kind: PlaybackKind.telegramFallback,
            version: version,
            message: 'Ce média ne peut pas être lu dans l\'application. Ouvrez-le dans Telegram.',
          );
        }
        return PlaybackPlan(
          kind: PlaybackKind.unavailable,
          version: version,
          failure: const MediaAccessException.inaccessible(),
        );
      }

      // 3. Lecture sur téléchargement en cours (flux contigu du `.part`).
      return PlaybackPlan(
        kind: PlaybackKind.partialStream,
        fileId: info.fileId,
        version: version,
        expectedBytes: snapshot.expectedBytes ?? info.expectedSize,
        message: 'Préparation de la lecture…',
      );
    } on MediaAccessException catch (failure) {
      if (version.hasTelegramLink) {
        return PlaybackPlan(
          kind: PlaybackKind.telegramFallback,
          version: version,
          failure: failure,
          message: 'Lecture directe indisponible.',
        );
      }
      return PlaybackPlan(kind: PlaybackKind.unavailable, version: version, failure: failure);
    } on GatewayError catch (error) {
      // État du fichier illisible (supprimé, cache perdu…) : repli propre
      // vers le lien Telegram réel — jamais de plantage.
      final MediaAccessException failure = MediaAccessException.fromGateway(error);
      if (version.hasTelegramLink) {
        return PlaybackPlan(
          kind: PlaybackKind.telegramFallback,
          version: version,
          failure: failure,
          message: 'Lecture directe indisponible.',
        );
      }
      return PlaybackPlan(kind: PlaybackKind.unavailable, version: version, failure: failure);
    }
  }

  /// Localise le fichier partiel TDLib (lecture progressive) pour un fileId.
  Future<String?> partialPathFor(int fileId) async {
    if (!canAccessTelegram) return null;
    try {
      final GatewayFileSnapshot snapshot = await gateway!.getFileSnapshot(fileId);
      return snapshot.localPath;
    } on GatewayError {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Téléchargements (délégation au DownloadManager)
  // -------------------------------------------------------------------------

  /// Construit une demande de téléchargement depuis les modèles d'écran.
  DownloadRequest buildDownloadRequest({
    required Anime anime,
    required Season season,
    required Episode episode,
    required EpisodeQuality version,
  }) {
    return DownloadRequest(
      versionId: version.id,
      animeId: anime.id,
      seasonId: season.id,
      episodeId: episode.id,
      animeTitle: anime.title,
      seasonNumber: season.number,
      episodeNumber: episode.number,
      chatId: version.sourceChannelId != null ? int.tryParse(version.sourceChannelId!) : null,
      messageId: version.telegramMessageId,
      channelUsername: version.sourceChannelUsername,
      messageLink: version.telegramMessageLink,
      qualityLabel: version.quality.label,
      language: version.language,
      expectedSize: version.size > 0 ? version.size : null,
      fileName: version.resolution.contains('.')
          ? version.resolution
          : null,
    );
  }

  Future<DownloadManagerResult> startDownload({
    required Anime anime,
    required Season season,
    required Episode episode,
    required EpisodeQuality version,
  }) {
    return downloadManager.enqueue(
      buildDownloadRequest(anime: anime, season: season, episode: episode, version: version),
    );
  }

  Future<void> pauseDownload(String versionId) => downloadManager.pause(versionId);

  Future<void> resumeDownload(String versionId) => downloadManager.resume(versionId);

  Future<void> cancelDownload(String versionId) => downloadManager.cancel(versionId);

  Future<void> deleteDownload(String versionId) => downloadManager.delete(versionId);

  // -------------------------------------------------------------------------
  // Ouverture dans Telegram (règle 28) — uniquement un lien RÉEL
  // -------------------------------------------------------------------------

  /// Ouvre la publication Telegram réelle. Renvoie un message d'erreur
  /// (ou null en cas de succès). N'invente JAMAIS de lien.
  Future<String?> openTelegramLink(String? link) async {
    if (link == null || link.isEmpty) {
      return 'Aucun lien Telegram disponible pour cette version.';
    }
    final Uri? uri = Uri.tryParse(link);
    if (uri == null || !uri.hasScheme) {
      return 'Aucun lien Telegram valide pour cette version.';
    }
    try {
      final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) return 'Impossible d\'ouvrir Telegram.';
      return null;
    } catch (_) {
      return 'Impossible d\'ouvrir Telegram.';
    }
  }
}
