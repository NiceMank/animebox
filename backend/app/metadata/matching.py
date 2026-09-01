"""Correspondance titre détecté ↔ candidat de métadonnées.

Objectifs :
- associer « Solo Leveling » au bon animé avec une confiance élevée ;
- NE PAS associer automatiquement « One Piece » à « One Piece Film: Red » ;
- classer les correspondances moyennes en « revue requise » au lieu de
  choisir au hasard.

La comparaison se fait sur des titres NORMALISÉS (mêmes règles que le
moteur d'analyse : casse, accents, séparateurs), et prend en compte les
titres canoniques, originaux et alternatifs du candidat, ainsi que l'année
lorsqu'elle est connue.
"""

from __future__ import annotations

from difflib import SequenceMatcher

from ..analyzer.text_utils import normalize
from .base import MetadataCandidate

# Seuils de décision.
MATCH_CONFIDENT = 0.85  # ≥ : association automatique
MATCH_REVIEW = 0.55  # ≥ et < CONFIDENT : revue requise
# < REVIEW : aucune correspondance fiable


def _similarity(query: str, candidate: MetadataCandidate) -> tuple[float, str | None]:
    """Meilleure similarité entre la requête et les titres du candidat."""
    best: tuple[float, str | None] = (0.0, None)
    candidates = [
        (candidate.title, "title"),
        (candidate.original_title, "original_title"),
        *((alt, "alternative_title") for alt in candidate.alternative_titles),
    ]
    for title, label in candidates:
        if not title:
            continue
        norm = normalize(title)
        ratio = SequenceMatcher(None, query, norm).ratio()
        if ratio > best[0]:
            best = (ratio, label)
    return best


def score_candidate(
    query: str,
    candidate: MetadataCandidate,
    known_year: int | None = None,
) -> float:
    """Score de correspondance dans [0, 1]."""
    query = normalize(query)
    if not query:
        return 0.0

    exact_kinds = ("title", "original_title", "alternative_title")
    similarity, matched_kind = _similarity(query, candidate)

    if similarity >= 1.0:
        # Égalité exacte : titre canonique ou titre alternatif.
        base = 0.98 if matched_kind == "title" else 0.92
        matched_by = matched_kind
    else:
        coverage = min(1.0, len(query.split()) / max(1, len(normalize(candidate.title).split())))
        # Pénalise fortement les titres plus longs que la requête
        # (« One Piece Film: Red » vs « one piece ») et les variantes
        # (« Solo Leveling Special » vs « solo leveling »).
        base = similarity * (0.60 + 0.40 * coverage) * 1.05
        matched_by = "fuzzy"

    score = min(0.99, base)

    # Année connue : bonus si identique, pénalité si différente.
    if known_year and candidate.year:
        if candidate.year == known_year:
            score = min(0.99, score + 0.05)
        else:
            score = score * 0.75

    candidate.similarity = round(score, 4)
    candidate.matched_by = matched_by
    return candidate.similarity


def classify_match(score: float) -> str:
    """'confident' (auto) · 'review' (revue requise) · 'none' (introuvable)."""
    if score >= MATCH_CONFIDENT:
        return "confident"
    if score >= MATCH_REVIEW:
        return "review"
    return "none"
