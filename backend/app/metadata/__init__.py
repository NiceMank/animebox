"""Fournisseurs de métadonnées d'animés.

Le backend peut être branché sur plusieurs fournisseurs derrière une même
interface ([MetadataProvider]) :

    MetadataService
        ├── JikanProvider   (distant — API publique Jikan/MyAnimeList, sans clé)
        └── LocalMetadataProvider (local — catalogue intégré, hors-ligne/tests)

Aucune clé secrète n'est nécessaire ; si un futur fournisseur en exige une,
elle vivra dans une variable d'environnement côté serveur (jamais dans
l'application mobile ni dans le dépôt).
"""

from .base import (  # noqa: F401
    MetadataAnime,
    MetadataCandidate,
    MetadataEpisode,
    MetadataProvider,
    MetadataSeason,
    ProviderError,
)
from .matching import (  # noqa: F401
    MATCH_CONFIDENT,
    MATCH_REVIEW,
    classify_match,
    score_candidate,
)

__all__ = [
    "MetadataAnime",
    "MetadataCandidate",
    "MetadataEpisode",
    "MetadataProvider",
    "MetadataSeason",
    "ProviderError",
    "MATCH_CONFIDENT",
    "MATCH_REVIEW",
    "classify_match",
    "score_candidate",
]
