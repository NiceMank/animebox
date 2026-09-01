"""Moteur principal : interface abstraite + implémentation déterministe.

``Analyzer`` est l'interface commune : une future implémentation
``AIAnalyzer`` (modèle externe) pourra s'insérer sans modifier le reste
du pipeline. ``RuleBasedAnalyzer`` fonctionne SANS aucune API d'IA :
expressions régulières, normalisation, dictionnaires, scoring et
correspondance avec le catalogue de titres.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass

from .aliases import AliasRegistry
from .extractors import TextAnalysis, analyze_text
from .models import MEDIA_TYPES, AnalysisResult
from .quality import infer_from_resolution, rank_of
from .scoring import score_analysis
from .text_utils import normalize, strip_extension

logger = logging.getLogger("animebox.analyzer")

AUDIO_EXTENSIONS = {".mp3", ".m4a", ".aac", ".flac", ".ogg", ".opus", ".wav"}
VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".webm", ".mov", ".m4v", ".ts", ".m2ts"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
SUBTITLE_EXTENSIONS = {".srt", ".ass", ".ssa", ".vtt"}


@dataclass
class EngineConfig:
    """Stratégie de priorité des informations (configurable).

    Ordre par défaut (du plus fiable au moins fiable) :
        1. métadonnées du fichier (durée, dimensions…)  → gérées à part
        2. nom du fichier
        3. caption Telegram
        4. texte du message
    """

    text_field_order: tuple[str, ...] = ("file_name", "text")


class Analyzer(ABC):
    """Interface abstraite du moteur d'analyse."""

    name = "abstract"

    @abstractmethod
    def analyze(self, message: dict, context: dict | None = None) -> AnalysisResult:
        """Analyse une publication Telegram (dict) et renvoie un résultat structuré."""


class RuleBasedAnalyzer(Analyzer):
    """Implémentation déterministe (aucune API d'IA externe)."""

    name = "rule-based"
    version = "1.0.0"

    def __init__(self, registry: AliasRegistry | None = None, config: EngineConfig | None = None):
        self.registry = registry or AliasRegistry()
        self.config = config or EngineConfig()

    # ------------------------------------------------------------------ API

    def analyze(self, message: dict, context: dict | None = None) -> AnalysisResult:
        message = {str(key): value for key, value in (message or {}).items()}

        # 1. Sources de texte, dans l'ordre de priorité configuré.
        file_name = strip_extension(message.get("file_name"))
        text = message.get("text") or message.get("caption")
        sources: list[TextAnalysis] = []
        for label in self.config.text_field_order:
            raw = file_name if label == "file_name" else text
            if raw and str(raw).strip():
                sources.append(analyze_text(normalize(raw), label, self.registry))

        # 2. Fusion des sources (la plus prioritaire l'emporte par champ).
        result = self._merge(sources, message)

        # 3. Qualité déduite des métadonnées du fichier si aucune valeur explicite.
        width = _as_int(message.get("width"))
        height = _as_int(message.get("height"))
        if result.quality is None and (width or height):
            inferred = infer_from_resolution(width, height)
            if inferred is not None:
                result.quality = inferred
                result.quality_original = f"{width}x{height}"
                result.quality_source = "metadata"
                result.quality_rank = rank_of(inferred)

        # 4. Informations du fichier (jamais inventées : None si absentes).
        result.file_name = message.get("file_name")
        result.file_size = _as_int(message.get("file_size"))
        result.mime_type = message.get("mime_type")
        result.duration = _as_int(message.get("duration"))
        result.width = width
        result.height = height

        # 5. Type de média.
        result.media_type = self._media_type(message)

        # 6. Références Telegram (conservées pour remonter à la publication).
        result.telegram_channel_id = message.get("telegram_channel_id") or message.get("channel_id")
        result.telegram_channel_username = message.get("telegram_channel_username") or message.get("channel_username")
        result.telegram_message_id = _as_int(message.get("telegram_message_id") or message.get("message_id"))
        result.telegram_message_link = message.get("telegram_message_link") or message.get("link")

        # 7. Score de confiance et statut.
        result.confidence, result.status = score_analysis(result)

        logger.info(
            "[Analyzer] %s | %s | S%s E%s | %s | %s | %s%% (%s)",
            result.telegram_message_id if result.telegram_message_id is not None else "-",
            result.title or "?",
            result.season if result.season is not None else "?",
            result.episode if result.episode is not None else "?",
            result.quality or "?",
            result.language or "?",
            result.confidence,
            result.status,
        )
        return result

    # ------------------------------------------------------------- internes

    def _merge(self, sources: list[TextAnalysis], message: dict) -> AnalysisResult:
        result = AnalysisResult()

        def first_value(attribute: str):
            """Première source (ordre de priorité) qui renseigne l'attribut."""
            for source in sources:
                value = getattr(source.extraction, attribute)
                if value is not None:
                    return value, source
            return None, None

        for attribute, target, source_target in (
            ("season", "season", "season_source"),
            ("year", "year", None),
        ):
            value, source = first_value(attribute)
            setattr(result, target, value)
            if source_target and value is not None:
                setattr(result, source_target, getattr(source.extraction, source_target))

        # Épisode (numéro + type « spécial »).
        value, source = first_value("episode")
        result.episode = value
        result.episode_source = getattr(source.extraction, "episode_source", None) if value is not None else None
        value, source = first_value("episode_kind")
        result.episode_kind = value
        if result.episode is None and result.episode_kind is not None:
            result.episode_source = getattr(source.extraction, "episode_source", None)

        # Qualité explicite (la fusion garde la valeur de la source prioritaire).
        value, source = first_value("quality")
        result.quality = value
        if value is not None:
            result.quality_original = source.extraction.quality_original
            result.quality_source = "explicit"
            result.quality_rank = rank_of(value)

        # Langue et sous-titres : champs indépendants.
        value, source = first_value("language")
        result.language = value or "unknown"
        value, source = first_value("subtitles")
        result.subtitles = value

        # Titre : on préfère la source dont le titre est RECONNU au catalogue
        # (une caption complète l'emporte sur un nom de fichier tronqué),
        # sinon la source la plus prioritaire qui propose un titre.
        chosen = next(
            (source for source in sources if source.title.key and source.title.matched),
            None,
        )
        if chosen is None:
            chosen = next((source for source in sources if source.title.key), None)
        if chosen is not None:
            result.title = chosen.title.display
            result.title_key = chosen.title.key
            result.title_matched = chosen.title.matched
            result.title_via_alias = chosen.title.via_alias
            if chosen.title.anime is not None:
                result.anime_key = chosen.title.anime.key
                result.original_title = chosen.title.anime.original_title
                result.release_year = chosen.title.anime.release_year

        # Contradictions entre sources + avertissements cumulés.
        for field in ("season", "episode", "quality", "language", "year"):
            values = {
                getattr(source.extraction, field)
                for source in sources
                if getattr(source.extraction, field) is not None
            }
            if len(values) > 1:
                result.warnings.append(f"{field} contradictoire entre les sources : {sorted(str(v) for v in values)}")
        for source in sources:
            for warning in source.extraction.warnings:
                if warning not in result.warnings:
                    result.warnings.append(warning)
        return result

    @staticmethod
    def _media_type(message: dict) -> str:
        media = str(message.get("media_type") or "unknown").lower()
        if media not in MEDIA_TYPES:
            media = "unknown"
        file_name = str(message.get("file_name") or "").lower()
        mime = str(message.get("mime_type") or "").lower()
        extension = f".{file_name.rsplit('.', 1)[-1]}" if "." in file_name else ""
        if mime.startswith("audio/") or extension in AUDIO_EXTENSIONS:
            return "audio"
        if mime.startswith("video/") or extension in VIDEO_EXTENSIONS:
            return "video"
        if mime.startswith("image/") or extension in IMAGE_EXTENSIONS:
            return "image"
        if extension in SUBTITLE_EXTENSIONS:
            return "document"  # fichier de sous-titres
        if media == "video" and mime:
            return "video"
        return media


def _as_int(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None
