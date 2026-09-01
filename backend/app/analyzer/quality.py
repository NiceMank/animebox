"""Détection et classement des qualités vidéo.

Valeurs reconnues (avec normalisation) :

    2160p / 4K / UHD           → 2160p   (rang 6)
    1440p / 2K / QHD           → 1440p   (rang 5)
    1080p / 1080 / FHD         → 1080p   (rang 4)
    720p  / 720  / HD / HDRIP  → 720p    (rang 3)
    480p  / 480  / SD          → 480p    (rang 2)
    360p  / 360                → 360p    (rang 1)

La valeur d'origine est conservée à côté de la valeur canonique, et le
rang permet de comparer les versions (« quelle est la meilleure ? »).
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class QualitySpec:
    canonical: str
    rank: int
    tokens: tuple[str, ...]  # formes reconnues dans le texte normalisé


QUALITY_SPECS: tuple[QualitySpec, ...] = (
    QualitySpec("2160p", 6, ("2160p", "4k", "uhd", "2160", "3840x2160")),
    QualitySpec("1440p", 5, ("1440p", "2k", "qhd", "1440", "2560x1440")),
    QualitySpec("1080p", 4, ("1080p", "1080", "fhd", "fullhd", "full hd", "1920x1080")),
    QualitySpec("720p", 3, ("720p", "720", "hd", "hdrip", "1280x720")),
    QualitySpec("480p", 2, ("480p", "480", "sd", "854x480")),
    QualitySpec("360p", 1, ("360p", "360", "640x360")),
)

# « HD → 720p », « FHD → 1080p » : alias normalisés.
_TOKEN_TO_SPEC: dict[str, QualitySpec] = {
    token: spec for spec in QUALITY_SPECS for token in spec.tokens
}

# Rang d'une valeur canonique (0 si inconnue).
RANK_BY_CANONICAL: dict[str, int] = {
    spec.canonical: spec.rank for spec in QUALITY_SPECS
}


def spec_for_token(token: str) -> QualitySpec | None:
    """Renvoie la spécification correspondant à un mot normalisé, ou None."""
    return _TOKEN_TO_SPEC.get(token)


def rank_of(quality: str | None) -> int:
    """Rang d'une qualité canonique (0 = inconnue)."""
    return RANK_BY_CANONICAL.get(quality or "", 0)


def canonical_rank(quality: str | None) -> int:
    """Rang de comparaison, inconnu = 0 (jamais préféré)."""
    return rank_of(quality)


def infer_from_resolution(width: int | None, height: int | None) -> str | None:
    """Déduit une qualité à partir des dimensions du fichier, si disponibles.

    Ne renvoie jamais de valeur inventée : sans dimensions, le résultat est
    None (la qualité reste « unknown »).
    """
    if not width or not height:
        return None
    if width >= 3200:
        return "2160p"
    if width >= 2400:
        return "1440p"
    if width >= 1800:
        return "1080p"
    if width >= 1200:
        return "720p"
    if width >= 800:
        return "480p"
    if width >= 600:
        return "360p"
    return None
