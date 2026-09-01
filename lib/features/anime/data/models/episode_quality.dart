import 'video_quality.dart';

/// Formate un nombre d'octets en taille lisible (« 1.2 GB », « 650 MB »).
String formatBytes(int bytes) {
  const int kb = 1024;
  const int mb = kb * 1024;
  const int gb = mb * 1024;
  if (bytes >= gb) {
    final double value = bytes / gb;
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} GB';
  }
  if (bytes >= mb) {
    final double value = bytes / mb;
    return '${value.toStringAsFixed(value >= 100 ? 0 : 0)} MB';
  }
  return '${(bytes / kb).round()} KB';
}

/// Une version téléchargeable d'un épisode (une qualité précise).
///
/// Plusieurs [EpisodeQuality] appartiennent au MÊME épisode : elles
/// représentent les différentes qualités/langues disponibles pour celui-ci.
///
/// Dans une étape ultérieure, ce modèle portera aussi les références
/// Telegram (telegramMessageId, telegramChannelId, telegramMessageLink,
/// fileId) lorsque les publications seront analysées par le moteur.
class EpisodeQuality {
  const EpisodeQuality({
    required this.id,
    required this.quality,
    required this.resolution,
    required this.size,
    required this.language,
    required this.subtitles,
    this.isAvailable = true,
    this.sourceChannelId,
    this.sourceChannelUsername,
    this.telegramMessageId,
    this.telegramMessageLink,
  });

  final String id;

  /// Qualité vidéo normalisée (1080p, 720p…).
  final VideoQuality quality;

  /// Résolution courte (« FHD », « HD », « SD »).
  final String resolution;

  /// Taille en octets — 0 si le fichier ne l'a pas exposée (jamais inventée).
  final int size;

  /// Langue audio (« VF », « VO », « VOSTFR »…).
  final String language;

  /// Sous-titres disponibles (« Aucun », « FR »…).
  final String subtitles;

  /// Disponibilité locale de cette version.
  final bool isAvailable;

  // ---- Références Telegram de la publication d'origine (étape 6) ----

  final String? sourceChannelId;
  final String? sourceChannelUsername;
  final int? telegramMessageId;
  final String? telegramMessageLink;

  /// Lien t.me valide — jamais inventé : `null`/vide si non constructible.
  bool get hasTelegramLink => telegramMessageLink != null && telegramMessageLink!.isNotEmpty;

  String get sizeLabel => formatBytes(size);
}
