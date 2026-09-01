/// Modèles du moteur d'analyse local — port fidèle de
/// `backend/app/analyzer/models.py` (sans dépendance Telegram).
library;

import 'language.dart';

const String kStatusHigh = 'high';
const String kStatusMedium = 'medium';
const String kStatusLow = 'low';
const String kStatusNeedsReview = 'needs_review';

/// Statuts suffisamment fiables pour alimenter le catalogue automatiquement.
const Set<String> kIngestibleStatuses = {kStatusHigh, kStatusMedium};

/// Résultat complet de l'analyse d'une publication.
class AnalysisResult {
  AnalysisResult({
    this.status = kStatusNeedsReview,
    this.confidence = 0,
    this.title,
    this.titleKey,
    this.titleMatched = false,
    this.titleViaAlias = false,
    this.animeKey,
    this.originalTitle,
    this.releaseYear,
    this.season,
    this.seasonSource,
    this.episode,
    this.episodeKind,
    this.episodeSource,
    this.year,
    this.quality,
    this.qualityOriginal,
    this.qualitySource,
    this.qualityRank = 0,
    this.language = kLanguageUnknown,
    this.subtitles,
    this.mediaType = 'unknown',
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.duration,
    this.width,
    this.height,
    this.telegramChannelId,
    this.telegramChannelUsername,
    this.telegramMessageId,
    this.telegramMessageLink,
    List<String>? warnings,
  }) : warnings = warnings ?? [];

  String status;
  int confidence;
  String? title;
  String? titleKey;
  bool titleMatched;
  bool titleViaAlias;
  String? animeKey;
  String? originalTitle;
  int? releaseYear;
  int? season;
  String? seasonSource;
  int? episode;
  String? episodeKind;
  String? episodeSource;
  int? year;
  String? quality;
  String? qualityOriginal;
  String? qualitySource;
  int qualityRank;
  String language;
  String? subtitles;
  String mediaType;
  String? fileName;
  int? fileSize;
  String? mimeType;
  int? duration;
  int? width;
  int? height;
  String? telegramChannelId;
  String? telegramChannelUsername;
  int? telegramMessageId;
  String? telegramMessageLink;
  List<String> warnings;

  /// Ligne de log lisible (jamais de secret).
  String display() {
    final String season = this.season != null ? 'S${this.season!.toString().padLeft(2, '0')}' : 'S?';
    final String episode = this.episode != null ? 'E${this.episode!.toString().padLeft(2, '0')}' : 'E?';
    return '${title ?? '?'} $season$episode ${quality ?? '?'} $language '
        '$confidence% [$status]';
  }

  Map<String, Object?> toMap() => {
        'status': status,
        'confidence': confidence,
        'title': title,
        'title_key': titleKey,
        'title_matched': titleMatched,
        'title_via_alias': titleViaAlias,
        'anime_key': animeKey,
        'original_title': originalTitle,
        'release_year': releaseYear,
        'season': season,
        'season_source': seasonSource,
        'episode': episode,
        'episode_kind': episodeKind,
        'episode_source': episodeSource,
        'year': year,
        'quality': quality,
        'quality_original': qualityOriginal,
        'quality_source': qualitySource,
        'quality_rank': qualityRank,
        'language': language,
        'subtitles': subtitles,
        'media_type': mediaType,
        'file_name': fileName,
        'file_size': fileSize,
        'mime_type': mimeType,
        'duration': duration,
        'width': width,
        'height': height,
        'telegram_channel_id': telegramChannelId,
        'telegram_channel_username': telegramChannelUsername,
        'telegram_message_id': telegramMessageId,
        'telegram_message_link': telegramMessageLink,
        'warnings': warnings,
      };
}
