"""Score de confiance et niveaux de fiabilité.

Le score (0–100) agrège la solidité de chaque détection :

    titre reconnu au catalogue          +33
    titre reconnu via un alias          +26
    titre non reconnu mais présent      +14
    saison explicite                    +15
    épisode explicite (S02E08, Ep 8)    +22
    épisode déduit (numéro seul)        +10
    épisode « spécial »                 +8
    qualité explicite                   +15
    qualité déduite des métadonnées     +10
    langue explicite                    +10
    sous-titres explicites              +5
    année cohérente avec le catalogue   +5
    format combiné SxE                  +3
    contradictions détectées            −10 chacune

Niveaux :  ≥ 85 HIGH · ≥ 65 MEDIUM · ≥ 40 LOW · sinon NEEDS_REVIEW.
Une analyse insuffisamment sûre n'est PAS classée aveuglément : elle reste
en attente de revue (statut needs_review).

Exemple de référence : « Solo Leveling S02E08 1080p VF » → 98 % (HIGH).
"""

from __future__ import annotations

from .models import (
    STATUS_HIGH,
    STATUS_LOW,
    STATUS_MEDIUM,
    STATUS_NEEDS_REVIEW,
    AnalysisResult,
)

LEVEL_HIGH = 85
LEVEL_MEDIUM = 65
LEVEL_LOW = 40


def score_analysis(result: AnalysisResult) -> tuple[int, str]:
    """Calcule (confiance, statut) pour une analyse."""
    points = 0

    # Titre
    if result.title_matched and result.anime_key:
        points += 26 if result.title_via_alias else 33
    elif result.title_key:
        points += 14

    # Saison
    if result.season is not None:
        points += 15

    # Épisode
    if result.episode_source in ("combined", "standalone"):
        points += 22
    elif result.episode_source == "heuristic_known":
        points += 18
    elif result.episode_source == "heuristic":
        points += 10
    elif result.episode_kind == "special":
        points += 8

    # Qualité
    if result.quality_source == "explicit":
        points += 15
    elif result.quality_source == "metadata":
        points += 10

    # Langue
    if result.language not in (None, "unknown"):
        points += 10

    # Sous-titres
    if result.subtitles is not None:
        points += 5

    # Année cohérente avec l'année de sortie connue du catalogue
    if (
        result.year is not None
        and result.release_year is not None
        and result.year == result.release_year
    ):
        points += 5

    # Format combiné S02E08 / 2x08 : très fiable
    if (
        result.season_source == "combined"
        and result.episode_source == "combined"
    ):
        points += 3

    # Contradictions détectées : pénalité
    points -= 10 * len(result.warnings)
    points = max(0, min(points, 99))

    if result.title_key is None:
        status = STATUS_NEEDS_REVIEW
    elif points >= LEVEL_HIGH:
        status = STATUS_HIGH
    elif points >= LEVEL_MEDIUM:
        status = STATUS_MEDIUM
    elif points >= LEVEL_LOW:
        status = STATUS_LOW
    else:
        status = STATUS_NEEDS_REVIEW
    return points, status
