"""Moteur d'analyse des publications Telegram — AnimeBox.

Pipeline déterministe (sans IA externe) :

    Message Telegram
        → nettoyage / normalisation        (text_utils)
        → détection saison / épisode       (extractors)
        → détection qualité                (quality)
        → détection langue / sous-titres   (language)
        → extraction du titre              (extractors + aliases)
        → score de confiance               (scoring)
        → regroupement des versions        (grouping)
        → persistance (catalogue)          (storage)
        → traitement par lot + cache       (batch)

L'interface abstraite ``Analyzer`` permet d'ajouter plus tard un
``AIAnalyzer`` sans toucher au reste du pipeline.
"""

from .engine import Analyzer, EngineConfig, RuleBasedAnalyzer  # noqa: F401
from .models import (  # noqa: F401
    MEDIA_TYPES,
    STATUS_HIGH,
    STATUS_LOW,
    STATUS_MEDIUM,
    STATUS_NEEDS_REVIEW,
    AnalysisResult,
)

__version__ = "1.0.0"
