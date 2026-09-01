"""Priorité des sources/versions d'un épisode.

Prépare le choix de la « meilleure » version selon des critères explicites
— sans JAMAIS supprimer les autres versions, qui restent toutes accessibles.

Critères (dans l'ordre) :
    1. qualité (2160p > 1440p > 1080p > 720p > 480p > 360p) ;
    2. langue (préférence configurable : VF > MULTI > VO/JP > autre) ;
    3. sous-titres français présents ;
    4. taille de fichier (version plus complète) ;
    5. fraîcheur (création la plus récente).
"""

from __future__ import annotations

# Préférence de langue de l'audience francophone (ordre décroissant).
LANGUAGE_PREFERENCE = ("french", "multi", "japanese", "english")


def language_score(version: dict) -> float:
    language = (version.get("language") or "").lower()
    if language in LANGUAGE_PREFERENCE:
        return float(len(LANGUAGE_PREFERENCE) - LANGUAGE_PREFERENCE.index(language))
    return 0.0


def version_sort_key(version: dict) -> tuple:
    """Clé de tri : plus la valeur est grande, meilleure est la version."""
    subtitles = (version.get("subtitles") or "").lower()
    return (
        int(version.get("quality_rank") or 0),
        language_score(version),
        1.0 if subtitles == "french" else 0.0,
        int(version.get("file_size") or 0),
        version.get("created_at") or "",
    )


def best_version(versions: list[dict]) -> dict | None:
    """Meilleure version d'une liste (les autres restent disponibles)."""
    if not versions:
        return None
    return max(versions, key=version_sort_key)
