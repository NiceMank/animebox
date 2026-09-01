/// Moteur principal local — port fidèle de `backend/app/analyzer/engine.py`.
///
/// Analyse déterministe (aucune API externe) : normalisation, motifs,
/// dictionnaires, scoring et correspondance avec le catalogue de titres.
library;

import 'aliases.dart';
import 'extractors.dart';
import 'models.dart';
import 'quality.dart' as quality;
import 'scoring.dart';
import 'text_utils.dart';

const Set<String> audioExtensions = {'.mp3', '.m4a', '.aac', '.flac', '.ogg', '.opus', '.wav'};
const Set<String> videoExtensions = {'.mkv', '.mp4', '.avi', '.webm', '.mov', '.m4v', '.ts', '.m2ts'};
const Set<String> imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
const Set<String> subtitleExtensions = {'.srt', '.ass', '.ssa', '.vtt'};
const Set<String> mediaTypes = {'video', 'document', 'image', 'audio', 'text', 'unknown'};

/// Stratégie de priorité des informations (configurable).
class EngineConfig {
  const EngineConfig({this.textFieldOrder = const ['file_name', 'text']});

  /// Ordre du plus fiable au moins fiable : nom de fichier, puis texte.
  final List<String> textFieldOrder;
}

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Analyse une publication Telegram (map) et renvoie un résultat structuré.
///
/// La map est volontairement identique au format du moteur Python :
/// `file_name`, `text`/`caption`, `file_size`, `mime_type`, `duration`,
/// `width`, `height`, `telegram_channel_id`/`channel_id`,
/// `telegram_channel_username`/`channel_username`,
/// `telegram_message_id`/`message_id`, `telegram_message_link`/`link`,
/// `media_type`.
class RuleBasedAnalyzer {
  RuleBasedAnalyzer({AliasRegistry? registry, EngineConfig? config})
      : registry = registry ?? AliasRegistry(),
        config = config ?? const EngineConfig();

  final AliasRegistry registry;
  final EngineConfig config;

  AnalysisResult analyze(Map<String, Object?> message) {
    // 1. Sources de texte, dans l'ordre de priorité configuré.
    final String? fileName = stripExtension(message['file_name']?.toString());
    final Object? rawText = message['text'] ?? message['caption'];
    final List<TextAnalysis> sources = [];
    for (final String label in config.textFieldOrder) {
      final String? raw = label == 'file_name' ? fileName : rawText?.toString();
      if (raw != null && raw.trim().isNotEmpty) {
        sources.add(analyzeText(normalize(raw), label, registry));
      }
    }

    // 2. Fusion des sources (la plus prioritaire l'emporte par champ).
    final AnalysisResult result = _merge(sources, message);

    // 3. Qualité déduite des métadonnées du fichier si aucune valeur explicite.
    final int? width = asInt(message['width']);
    final int? height = asInt(message['height']);
    if (result.quality == null && (width != null || height != null)) {
      final String? inferred = quality.inferFromResolution(width, height);
      if (inferred != null) {
        result.quality = inferred;
        result.qualityOriginal = '$width${height == null ? '' : 'x$height'}';
        result.qualitySource = 'metadata';
        result.qualityRank = quality.rankOf(inferred);
      }
    }

    // 4. Informations du fichier (jamais inventées : null si absentes).
    result.fileName = message['file_name']?.toString();
    result.fileSize = asInt(message['file_size']);
    result.mimeType = message['mime_type']?.toString();
    result.duration = asInt(message['duration']);
    result.width = width;
    result.height = height;

    // 5. Type de média.
    result.mediaType = _mediaType(message);

    // 6. Références Telegram (conservées pour remonter à la publication).
    result.telegramChannelId =
        (message['telegram_channel_id'] ?? message['channel_id'])?.toString();
    result.telegramChannelUsername =
        (message['telegram_channel_username'] ?? message['channel_username'])?.toString();
    result.telegramMessageId = asInt(message['telegram_message_id'] ?? message['message_id']);
    result.telegramMessageLink =
        (message['telegram_message_link'] ?? message['link'])?.toString();

    // 7. Score de confiance et statut.
    final (int confidence, String status) = scoreAnalysis(result);
    result.confidence = confidence;
    result.status = status;
    return result;
  }

  String _mediaType(Map<String, Object?> message) {
    String media = (message['media_type'] ?? 'unknown').toString().toLowerCase();
    if (!mediaTypes.contains(media)) media = 'unknown';
    final String fileName = (message['file_name'] ?? '').toString().toLowerCase();
    final String mime = (message['mime_type'] ?? '').toString().toLowerCase();
    final String extension = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
    if (mime.startsWith('audio/') || audioExtensions.contains(extension)) return 'audio';
    if (mime.startsWith('video/') || videoExtensions.contains(extension)) return 'video';
    if (mime.startsWith('image/') || imageExtensions.contains(extension)) return 'image';
    if (subtitleExtensions.contains(extension)) return 'document';
    if (media == 'video' && mime.isNotEmpty) return 'video';
    return media;
  }

  AnalysisResult _merge(List<TextAnalysis> sources, Map<String, Object?> message) {
    final AnalysisResult result = AnalysisResult();

    (Object?, TextAnalysis?) firstValue(String attribute) {
      for (final TextAnalysis source in sources) {
        final Object? value = _attributeOf(source.extraction, attribute);
        if (value != null) return (value, source);
      }
      return (null, null);
    }

    // Saison + année.
    final (Object? seasonValue, TextAnalysis? seasonSource) = firstValue('season');
    result.season = seasonValue as int?;
    if (seasonValue != null && seasonSource != null) {
      result.seasonSource = seasonSource.extraction.seasonSource;
    }
    final (Object? yearValue, _) = firstValue('year');
    result.year = yearValue as int?;

    // Épisode (numéro + type « spécial »).
    final (Object? episodeValue, TextAnalysis? episodeSource) = firstValue('episode');
    result.episode = episodeValue as int?;
    if (episodeValue != null && episodeSource != null) {
      result.episodeSource = episodeSource.extraction.episodeSource;
    }
    final (Object? kindValue, TextAnalysis? kindSource) = firstValue('episode_kind');
    result.episodeKind = kindValue as String?;
    if (result.episode == null && result.episodeKind != null && kindSource != null) {
      result.episodeSource = kindSource.extraction.episodeSource;
    }

    // Qualité explicite (la source prioritaire l'emporte).
    final (Object? qualityValue, TextAnalysis? qualitySource) = firstValue('quality');
    result.quality = qualityValue as String?;
    if (qualityValue != null && qualitySource != null) {
      result.qualityOriginal = qualitySource.extraction.qualityOriginal;
      result.qualitySource = 'explicit';
      result.qualityRank = quality.rankOf(result.quality);
    }

    // Langue et sous-titres : champs indépendants.
    final (Object? languageValue, _) = firstValue('language');
    result.language = (languageValue as String?) ?? 'unknown';
    final (Object? subtitlesValue, _) = firstValue('subtitles');
    result.subtitles = subtitlesValue as String?;

    // Titre : on préfère la source dont le titre est RECONNU au catalogue,
    // sinon la source la plus prioritaire qui propose un titre.
    TextAnalysis? chosen;
    for (final TextAnalysis source in sources) {
      if (source.title.key != null && source.title.matched) {
        chosen = source;
        break;
      }
    }
    chosen ??= sources.where((TextAnalysis s) => s.title.key != null).firstOrNull;
    if (chosen != null) {
      result.title = chosen.title.display;
      result.titleKey = chosen.title.key;
      result.titleMatched = chosen.title.matched;
      result.titleViaAlias = chosen.title.viaAlias;
      final AnimeTitle? anime = chosen.title.anime;
      if (anime != null) {
        result.animeKey = anime.key;
        result.originalTitle = anime.originalTitle;
        result.releaseYear = anime.releaseYear;
      }
    }

    // Contradictions entre sources + avertissements cumulés.
    for (final String field in const ['season', 'episode', 'quality', 'language', 'year']) {
      final Set<Object?> values = {
        for (final TextAnalysis source in sources)
          if (_attributeOf(source.extraction, field) != null) _attributeOf(source.extraction, field),
      };
      if (values.length > 1) {
        final List<String> sorted = values.map((Object? v) => v.toString()).toList()..sort();
        result.warnings.add('$field contradictoire entre les sources : $sorted');
      }
    }
    for (final TextAnalysis source in sources) {
      for (final String warning in source.extraction.warnings) {
        if (!result.warnings.contains(warning)) result.warnings.add(warning);
      }
    }
    return result;
  }

  static Object? _attributeOf(Extraction extraction, String attribute) => switch (attribute) {
        'season' => extraction.season,
        'year' => extraction.year,
        'episode' => extraction.episode,
        'episode_kind' => extraction.episodeKind,
        'quality' => extraction.quality,
        'language' => extraction.language,
        'subtitles' => extraction.subtitles,
        _ => null,
      };
}
