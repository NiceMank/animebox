import 'dart:io';

/// Organisation locale des fichiers téléchargés (règle 17) :
///
/// ```
/// <base>/AnimeBox/Solo Leveling/Season 02/S02E08 - 1080p - VF.mkv
/// ```
///
/// Les caractères invalides provenant des noms Telegram sont nettoyés.
abstract final class MediaPaths {
  MediaPaths._();

  /// Nom du dossier racine des médias AnimeBox (stockage privé de l'app).
  static const String rootFolder = 'AnimeBox';

  /// Nettoie un segment de nom (titre Telegram) pour le système de fichiers.
  static String sanitize(String raw) {
    final String cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Sans titre';
    // Les points finaux sont interdits sur Android (dossiers).
    return cleaned.replaceAll(RegExp(r'\.$'), '');
  }

  /// Extension vidéo réelle déduite du nom Telegram (défaut : .mp4).
  static String videoExtension(String? fileName) {
    final String name = fileName ?? '';
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.mp4';
    final String ext = name.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{2,5}$').hasMatch(ext) ? ext : '.mp4';
  }

  /// Chemin complet organisé d'une version téléchargée.
  static String organizedVideoPath({
    required String baseDirectory,
    required String animeTitle,
    required int seasonNumber,
    required int episodeNumber,
    String? qualityLabel,
    String? language,
    String? fileName,
  }) {
    final String seasonFolder =
        'Season ${seasonNumber.clamp(0, 99).toString().padLeft(2, '0')}';
    final String code =
        'S${seasonNumber.clamp(0, 99).toString().padLeft(2, '0')}E${episodeNumber.clamp(0, 999).toString().padLeft(2, '0')}';
    final List<String> parts = [
      code,
      if (qualityLabel != null && qualityLabel.isNotEmpty) qualityLabel,
      if (language != null && language.isNotEmpty) language,
    ];
    final String baseName = sanitize(parts.join(' - '));
    return _joinSegments([
      baseDirectory,
      rootFolder,
      sanitize(animeTitle),
      seasonFolder,
      '$baseName${videoExtension(fileName)}',
    ]);
  }

  /// Réécrit `p.join` localement pour rester testable sans import indirect.
  static String _joinSegments(List<String> segments) {
    String result = segments.first;
    for (final String segment in segments.skip(1)) {
      result = Platform.isWindows ? '$result\\$segment' : '$result/$segment';
    }
    return result;
  }
}
