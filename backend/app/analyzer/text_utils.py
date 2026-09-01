"""Normalisation de texte : étape 1 du pipeline.

Toutes les variantes de casse et de séparateurs sont réduites à une forme
canonique unique avant détection :

    Solo_Leveling_S02_E08_1080p   →  solo leveling s 02 e 08 1080p
    Solo.Leveling.S02E08.1080p    →  solo leveling s02e08 1080p
    SOLO LEVELING 08 VOSTFR       →  solo leveling 08 vostfr

La normalisation est appliquée à la fois aux textes analysés ET aux titres
du catalogue : la comparaison se fait donc toujours dans le même espace.
"""

from __future__ import annotations

import re
import unicodedata

# Séparateurs remplacés par des espaces (tiret, point, underscore, puce…).
_SEPARATOR_RE = re.compile(r"[\u00B7\u2022._\u2010\u2011\u2012\u2013\u2014-]+")
# Crochets et guillemets supprimés (remplacés par des espaces).
_BRACKETS_RE = re.compile(r"[\[\]\(\){}<>«»\"\u201C\u201D]+")
# Toute ponctuation résiduelle (apostrophes, deux-points, virgules…).
_PUNCT_RE = re.compile(r"[^0-9a-zàâäçéèêëîïôöùûüÿœæ\s]+")
_WS_RE = re.compile(r"\s+")

# Mots génériques qui ne peuvent pas constituer un titre à eux seuls
# (« Épisode 08 disponible » → aucun titre fiable).
GENERIC_WORDS = {
    "disponible",
    "available",
    "nouvel",
    "nouveau",
    "nouvelle",
    "new",
    "sortie",
    "dispo",
    "bonus",
    "bientot",
    "bientôt",
    "soon",
    "up",
    "de",
    "du",
    "episode",
    "épisode",
    "special",
    "spécial",
}


def normalize(text: str | None) -> str:
    """Normalise un texte libre pour la détection de motifs."""
    if not text:
        return ""
    value = unicodedata.normalize("NFKC", str(text)).lower()
    value = _SEPARATOR_RE.sub(" ", value)
    value = _BRACKETS_RE.sub(" ", value)
    value = _PUNCT_RE.sub(" ", value)
    return _WS_RE.sub(" ", value).strip()


class Token:
    """Mot normalisé avec sa position dans le texte normalisé."""

    __slots__ = ("text", "start", "end")

    def __init__(self, text: str, start: int, end: int):
        self.text = text
        self.start = start
        self.end = end

    def __repr__(self) -> str:  # pragma: no cover - debug
        return f"Token({self.text!r}@{self.start})"


def tokenize(normalized_text: str) -> list[Token]:
    """Découpe le texte normalisé en mots (aucune ponctuation ne subsiste)."""
    tokens: list[Token] = []
    for match in re.finditer(r"\S+", normalized_text or ""):
        tokens.append(Token(match.group(), match.start(), match.end()))
    return tokens


def tokens_to_text(tokens: list[Token]) -> str:
    """Rejoint des mots en texte normalisé."""
    return " ".join(token.text for token in tokens)


def titlecase(text: str) -> str:
    """Reconstruit un affichage propre (« solo leveling » → « Solo Leveling »)."""
    small = {
        "of", "the", "a", "an", "in", "on", "and", "et", "for", "to",
        "de", "la", "le", "les", "des", "du", "s",
    }
    words = (text or "").split()
    out: list[str] = []
    for index, word in enumerate(words):
        if word in small and index not in (0, len(words) - 1):
            out.append(word)
        else:
            out.append(word[:1].upper() + word[1:])
    return " ".join(out)


def strip_extension(file_name: str | None) -> str | None:
    """Retire l'extension d'un nom de fichier avant analyse."""
    if not file_name:
        return None
    return file_name.rsplit(".", 1)[0] if "." in file_name else file_name
