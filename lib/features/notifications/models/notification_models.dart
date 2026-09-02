/// Modèles du système de notification (prompt 9) :
/// résumé réel de synchronisation, épisodes concernés, charges utiles.
library;

import 'dart:convert';

// ---------------------------------------------------------------------------
// Résumé d'une synchronisation RÉELLE (règle 21)
// ---------------------------------------------------------------------------

/// Un épisode touché par une synchronisation : nouvel épisode OU nouvelle
/// qualité ajoutée à un épisode existant. Toutes les valeurs proviennent
/// de l'analyse réelle des publications — rien n'est inventé.
class SyncRunEpisode {
  const SyncRunEpisode({
    required this.episodeId,
    required this.animeId,
    required this.seasonId,
    required this.sourceId,
    required this.animeTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.isNewEpisode,
    required this.addedQualities,
    required this.totalQualities,
    this.qualityLabel,
    this.language,
  });

  final String episodeId;
  final String animeId;
  final String seasonId;

  /// Source Telegram d'origine de la publication analysée.
  final String sourceId;

  final String animeTitle;
  final int seasonNumber;
  final int episodeNumber;

  /// `true` quand l'épisode vient d'être créé (jamais vu avant).
  final bool isNewEpisode;

  /// Nombre de versions (qualités) ajoutées par CETTE synchronisation.
  final int addedQualities;

  /// Nombre total de versions réellement présentes en base après la passe.
  final int totalQualities;

  /// Étiquette de la meilleure qualité ajoutée (ex. « 1080p »).
  final String? qualityLabel;

  /// Langue détectée (ex. « VF »), si déterminée.
  final String? language;

  /// « S02E09 » — jamais inventé : uniquement à partir des numéros réels.
  String get seasonEpisodeLabel {
    final String s = seasonNumber.toString().padLeft(2, '0');
    final String e = episodeNumber.toString().padLeft(2, '0');
    return 'S${s}E$e';
  }
}

/// Bilan complet d'une passe de synchronisation (manuelle ou automatique).
/// Affiché tel quel à l'utilisateur (règle 21 : valeurs réelles) et
/// consommé par le centre de notifications (règles 4/5/6).
class SyncRunSummary {
  const SyncRunSummary({
    required this.finishedAt,
    this.sourcesAnalyzed = 0,
    this.newMessages = 0,
    this.newEpisodes = 0,
    this.newQualities = 0,
    this.errors = 0,
    this.errorMessages = const <String>[],
    this.cancelled = false,
    this.episodes = const <SyncRunEpisode>[],
  });

  final DateTime finishedAt;

  /// Sources réellement synchronisées (les sources désactivées sont
  /// exclues avant le départ — règle 16).
  final int sourcesAnalyzed;

  /// Publications réellement analysées pendant la passe.
  final int newMessages;

  /// Épisodes créés (jamais vus auparavant).
  final int newEpisodes;

  /// Versions ajoutées à des épisodes déjà connus.
  final int newQualities;

  /// Sources en échec (accessibilité, réseau, session…).
  final int errors;
  final List<String> errorMessages;

  /// La passe a été annulée avant la fin.
  final bool cancelled;

  /// Tous les épisodes touchés (nouveaux ET enrichis d'une qualité).
  final List<SyncRunEpisode> episodes;

  bool get hasErrors => errors > 0;
}

// ---------------------------------------------------------------------------
// Charge utile des notifications (clic → bon écran — règle 7)
// ---------------------------------------------------------------------------

/// Type de charge utile : épisode à ouvrir / téléchargement à lire ou
/// reprendre.
enum NotificationPayloadType { episode, downloadCompleted, downloadFailed }

/// Charge utile sérialisée d'une notification (JSON compact).
class AnimeBoxNotificationPayload {
  const AnimeBoxNotificationPayload({
    required this.type,
    this.animeId,
    this.seasonId,
    this.episodeId,
    this.versionId,
  });

  final NotificationPayloadType type;
  final String? animeId;
  final String? seasonId;
  final String? episodeId;
  final String? versionId;

  static const Map<NotificationPayloadType, String> _names =
      <NotificationPayloadType, String>{
    NotificationPayloadType.episode: 'episode',
    NotificationPayloadType.downloadCompleted: 'download_completed',
    NotificationPayloadType.downloadFailed: 'download_failed',
  };

  String encode() => jsonEncode(<String, Object?>{
        'type': _names[type],
        'animeId': animeId,
        'seasonId': seasonId,
        'episodeId': episodeId,
        'versionId': versionId,
      });

  /// Décodage tolérant : une charge illisible renvoie null (jamais de
  /// plantage à l'ouverture de l'application).
  static AnimeBoxNotificationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Map<String, Object?> map =
          (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, Object?>();
      final NotificationPayloadType type = switch (map['type']) {
        'episode' => NotificationPayloadType.episode,
        'download_completed' => NotificationPayloadType.downloadCompleted,
        'download_failed' => NotificationPayloadType.downloadFailed,
        _ => NotificationPayloadType.episode,
      };
      return AnimeBoxNotificationPayload(
        type: type,
        animeId: map['animeId']?.toString(),
        seasonId: map['seasonId']?.toString(),
        episodeId: map['episodeId']?.toString(),
        versionId: map['versionId']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Identifiants d'actions des notifications (boutons).
abstract final class NotificationActions {
  NotificationActions._();

  /// « Lire » — téléchargement terminé.
  static const String play = 'play';

  /// « Reprendre » — téléchargement interrompu.
  static const String resume = 'resume';
}

/// Hachage stable (FNV-1a, 31 bits) : un même épisode/téléchargement
/// conserve LE MÊME identifiant de notification — mise à jour en place
/// plutôt que doublons (règle 5).
int stableNotificationId(String key) {
  int hash = 0x811c9dc5;
  for (final int unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// Identifiant de notification d'un épisode.
int episodeNotificationId(String episodeId) => stableNotificationId('ep:$episodeId');

/// Identifiant de notification d'un téléchargement.
int downloadNotificationId(String versionId) => stableNotificationId('dl:$versionId');
