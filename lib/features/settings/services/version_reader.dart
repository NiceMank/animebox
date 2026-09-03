import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Lecture de la **version réelle du projet** (prompt 12 §21/§22) :
/// la ligne `version:` du `pubspec.yaml` embarqué comme asset Flutter.
/// Aucune valeur fictive — si la lecture échoue, l'écran affiche
/// « inconnue » (jamais un faux numéro).
class VersionReader {
  static const String assetPath = 'pubspec.yaml';

  final AssetBundle _bundle;

  const VersionReader({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  /// Extrait `x.y.z` (+build) du contenu d'un pubspec — logique pure,
  /// testable sans Flutter.
  static String? parseVersion(String pubspecContent) {
    for (final String line in pubspecContent.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.startsWith('version:')) {
        final String value = trimmed.substring('version:'.length).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Future<String?> read() async {
    try {
      final String content = await _bundle.loadString(assetPath);
      return parseVersion(content);
    } catch (_) {
      return null;
    }
  }
}
