import 'episode_quality.dart';
import 'video_quality.dart';

/// Une version d'épisode issue du catalogue Telegram (prompt étape 6).
///
/// Plusieurs [EpisodeVersion] appartiennent au MÊME épisode : chaque
/// publication Telegram (source, qualité, langue) est conservée comme une
/// version distincte — aucune n'est supprimée, la « meilleure » est seulement
/// proposée en premier.
class EpisodeVersion {
  const EpisodeVersion({
    required this.id,
    required this.quality,
    this.resolution,
    this.language,
    this.subtitles,
    this.sizeBytes,
    this.durationSec,
    this.mediaType,
    this.fileName,
    this.createdAt,
    this.sourceChannelId,
    this.sourceChannelUsername,
    this.telegramMessageId,
    this.telegramMessageLink,
  });

  factory EpisodeVersion.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? source = json['source'] as Map<String, dynamic>?;
    return EpisodeVersion(
      id: json['id'].toString(),
      quality: _qualityFromApi(json['quality']),
      resolution: json['resolution']?.toString(),
      language: json['language']?.toString(),
      subtitles: json['subtitles']?.toString(),
      sizeBytes: (json['file_size'] as num?)?.toInt(),
      durationSec: (json['duration'] as num?)?.toInt(),
      mediaType: json['media_type']?.toString(),
      fileName: json['file_name']?.toString(),
      createdAt: json['created_at']?.toString(),
      sourceChannelId: (source?['channel_id'] ?? json['source_id'])?.toString(),
      sourceChannelUsername: source?['channel_username']?.toString(),
      telegramMessageId: (source?['telegram_message_id'] ?? json['telegram_message_id']) as int?,
      telegramMessageLink:
          (source?['telegram_message_link'] ?? json['telegram_message_link'])?.toString(),
    );
  }

  /// Convertit une qualité brute de l'API (« 1080p », « 720p »…) en
  /// [VideoQuality]. Toute valeur inconnue est traitée en qualité basse.
  static VideoQuality _qualityFromApi(Object? value) {
    final String raw = value?.toString() ?? '';
    return switch (raw) {
      '1080p' => VideoQuality.fhd,
      '720p' => VideoQuality.hd,
      '480p' => VideoQuality.sd,
      '360p' => VideoQuality.low,
      _ => VideoQuality.low,
    };
  }

  final String id;

  /// Qualité normalisée (1080p, 720p, 480p, 360p).
  final VideoQuality quality;

  /// Résolution brute renvoyée par l'API (ex. « 1920x1080 »), si connue.
  final String? resolution;

  /// Langue audio (VF, VOSTFR, VO…).
  final String? language;

  /// Sous-titres (FR, Aucun…).
  final String? subtitles;

  /// Taille en octets (jamais inventée : absente si non mesurée).
  final int? sizeBytes;

  /// Durée en secondes (jamais inventée : absente si non mesurée).
  final int? durationSec;

  final String? mediaType;
  final String? fileName;

  /// Date de publication (ISO 8601), si connue.
  final String? createdAt;

  // ---- Traçabilité Telegram (jamais perdue) ----

  final String? sourceChannelId;
  final String? sourceChannelUsername;
  final int? telegramMessageId;
  final String? telegramMessageLink;

  /// Lien t.me valide (jamais construit artificiellement).
  bool get hasTelegramLink =>
      telegramMessageLink != null && telegramMessageLink!.isNotEmpty;

  /// Résolution courte pour l'affichage (FHD, HD, SD) — dérivée de la
  /// qualité normalisée, jamais inventée.
  String get resolutionLabel => quality.resolution;

  String get languageLabel => language ?? 'VO';

  /// Adapte cette version au modèle d'écran existant ([EpisodeQuality]) :
  /// les écrans de choix de qualité/lecture continuent de fonctionner tels
  /// quels, enrichis des références Telegram.
  EpisodeQuality toEpisodeQuality() => EpisodeQuality(
        id: id,
        quality: quality,
        resolution: resolutionLabel,
        size: sizeBytes ?? 0,
        language: languageLabel,
        subtitles: subtitles ?? 'Aucun',
        sourceChannelId: sourceChannelId,
        sourceChannelUsername: sourceChannelUsername,
        telegramMessageId: telegramMessageId,
        telegramMessageLink: telegramMessageLink,
      );
}
