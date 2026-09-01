/// Détection et classement des qualités vidéo — port fidèle de
/// `backend/app/analyzer/quality.py`.
library;

/// Spécification d'une qualité reconnue.
class QualitySpec {
  const QualitySpec(this.canonical, this.rank, this.tokens);

  final String canonical;
  final int rank;
  final List<String> tokens;
}

/// Valeurs reconnues (avec normalisation).
const List<QualitySpec> kQualitySpecs = [
  QualitySpec('2160p', 6, ['2160p', '4k', 'uhd', '2160', '3840x2160']),
  QualitySpec('1440p', 5, ['1440p', '2k', 'qhd', '1440', '2560x1440']),
  QualitySpec('1080p', 4, ['1080p', '1080', 'fhd', 'fullhd', 'full hd', '1920x1080']),
  QualitySpec('720p', 3, ['720p', '720', 'hd', 'hdrip', '1280x720']),
  QualitySpec('480p', 2, ['480p', '480', 'sd', '854x480']),
  QualitySpec('360p', 1, ['360p', '360', '640x360']),
];

final Map<String, QualitySpec> _tokenToSpec = {
  for (final QualitySpec spec in kQualitySpecs)
    for (final String token in spec.tokens) token: spec,
};

final Map<String, int> _rankByCanonical = {
  for (final QualitySpec spec in kQualitySpecs) spec.canonical: spec.rank,
};

/// Renvoie la spécification correspondant à un mot normalisé, ou null.
QualitySpec? specForToken(String token) => _tokenToSpec[token];

/// Rang d'une qualité canonique (0 = inconnue).
int rankOf(String? quality) => _rankByCanonical[quality] ?? 0;

/// Déduit une qualité à partir des dimensions du fichier (jamais inventée).
String? inferFromResolution(int? width, int? height) {
  if (width == null || height == null || width == 0 || height == 0) return null;
  if (width >= 3200) return '2160p';
  if (width >= 2400) return '1440p';
  if (width >= 1800) return '1080p';
  if (width >= 1200) return '720p';
  if (width >= 800) return '480p';
  if (width >= 600) return '360p';
  return null;
}
