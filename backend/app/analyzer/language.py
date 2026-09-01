"""Détection de la langue audio et des sous-titres.

Règles principales :

    VF / FR / FRENCH              → langue audio français
    VO / JAP / JAPANESE           → langue audio japonais (version originale)
    VOSTFR / VOST / SUBFR / SUBFR → audio original, sous-titres français
    SUB / SUBBED                  → sous-titres présents, langue inconnue
    MULTI                         → audio multi-langues

Aucune langue n'est supposée par défaut : sans indicateur, la langue est
« unknown » (jamais « japonais » deviné).
"""

from __future__ import annotations

from dataclasses import dataclass

LANGUAGE_UNKNOWN = "unknown"
SUBTITLES_UNKNOWN = "unknown"  # sous-titres mentionnés mais langue non précisée


@dataclass(frozen=True)
class LanguageMatch:
    language: str | None  # langue audio
    subtitles: str | None  # None = non mentionné ; "unknown" = mentionné sans langue


# Mot normalisé → (audio, sous-titres). L'ordre n'importe pas : la recherche
# se fait sur les mots exacts ; « vostfr » est un seul mot, jamais confondu
# avec « fr ».
_TOKEN_RULES: dict[str, LanguageMatch] = {
    # Audio français (VF)
    "vf": LanguageMatch("french", None),
    "vff": LanguageMatch("french", None),
    "truefrench": LanguageMatch("french", None),
    "french": LanguageMatch("french", None),
    "fr": LanguageMatch("french", None),
    # Version originale (audio japonais par défaut pour un animé)
    "vo": LanguageMatch("japanese", None),
    "vost": LanguageMatch("japanese", SUBTITLES_UNKNOWN),
    "jap": LanguageMatch("japanese", None),
    "japanese": LanguageMatch("japanese", None),
    "ja": LanguageMatch("japanese", None),
    # VO sous-titrée français
    "vostfr": LanguageMatch("japanese", "french"),
    "vostfrance": LanguageMatch("japanese", "french"),
    "subfr": LanguageMatch("japanese", "french"),
    "subfrench": LanguageMatch("japanese", "french"),
    # VO sous-titrée anglais
    "vosten": LanguageMatch("japanese", "english"),
    "suben": LanguageMatch("japanese", "english"),
    "subeng": LanguageMatch("japanese", "english"),
    # Audio anglais
    "english": LanguageMatch("english", None),
    "eng": LanguageMatch("english", None),
    "en": LanguageMatch("english", None),
    # Sous-titres seuls (audio inconnu)
    "sub": LanguageMatch(None, SUBTITLES_UNKNOWN),
    "subbed": LanguageMatch(None, SUBTITLES_UNKNOWN),
    # Multi
    "multi": LanguageMatch("multi", None),
    "multiaudio": LanguageMatch("multi", None),
}


def match_token(token: str) -> LanguageMatch | None:
    """Règle associée à un mot normalisé, ou None."""
    return _TOKEN_RULES.get(token)


def merge(
    current: LanguageMatch | None, incoming: LanguageMatch | None
) -> LanguageMatch | None:
    """Combine deux détections : la première renseignée l'emporte par champ.

    Exemple : « sub » puis « fr » → audio None, sous-titres français.
    """
    if current is None:
        return incoming
    if incoming is None:
        return current
    return LanguageMatch(
        language=current.language or incoming.language,
        subtitles=(
            current.subtitles
            if current.subtitles is not None
            else incoming.subtitles
        ),
    )
