/// Détection de la langue audio et des sous-titres — port fidèle de
/// `backend/app/analyzer/language.py`.
library;

const String kLanguageUnknown = 'unknown';
const String kSubtitlesUnknown = 'unknown';

/// Langue audio + sous-titres détectés.
class LanguageMatch {
  const LanguageMatch(this.language, this.subtitles);

  final String? language;
  final String? subtitles;
}

/// Mot normalisé → (audio, sous-titres).
const Map<String, LanguageMatch> _tokenRules = {
  // Audio français (VF)
  'vf': LanguageMatch('french', null),
  'vff': LanguageMatch('french', null),
  'truefrench': LanguageMatch('french', null),
  'french': LanguageMatch('french', null),
  'fr': LanguageMatch('french', null),
  // Version originale (audio japonais par défaut pour un animé)
  'vo': LanguageMatch('japanese', null),
  'vost': LanguageMatch('japanese', kSubtitlesUnknown),
  'jap': LanguageMatch('japanese', null),
  'japanese': LanguageMatch('japanese', null),
  'ja': LanguageMatch('japanese', null),
  // VO sous-titrée français
  'vostfr': LanguageMatch('japanese', 'french'),
  'vostfrance': LanguageMatch('japanese', 'french'),
  'subfr': LanguageMatch('japanese', 'french'),
  'subfrench': LanguageMatch('japanese', 'french'),
  // VO sous-titrée anglais
  'vosten': LanguageMatch('japanese', 'english'),
  'suben': LanguageMatch('japanese', 'english'),
  'subeng': LanguageMatch('japanese', 'english'),
  // Audio anglais
  'english': LanguageMatch('english', null),
  'eng': LanguageMatch('english', null),
  'en': LanguageMatch('english', null),
  // Sous-titres seuls (audio inconnu)
  'sub': LanguageMatch(null, kSubtitlesUnknown),
  'subbed': LanguageMatch(null, kSubtitlesUnknown),
  // Multi
  'multi': LanguageMatch('multi', null),
  'multiaudio': LanguageMatch('multi', null),
};

/// Règle associée à un mot normalisé, ou null.
LanguageMatch? matchToken(String token) => _tokenRules[token];

/// Combine deux détections : la première renseignée l'emporte par champ.
LanguageMatch? mergeMatches(LanguageMatch? current, LanguageMatch? incoming) {
  if (current == null) return incoming;
  if (incoming == null) return current;
  return LanguageMatch(
    current.language ?? incoming.language,
    current.subtitles ?? incoming.subtitles,
  );
}
