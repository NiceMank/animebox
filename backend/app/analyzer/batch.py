"""Traitement par lot des publications.

- cache : un message inchangé (même empreinte) n'est pas réanalysé ;
- ingestion : les analyses suffisamment fiables alimentent le catalogue ;
- logs : progression lisible, sans aucune donnée sensible ;
- erreurs : une publication en échec n'interrompt pas le lot.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from .engine import Analyzer
from .grouping import EpisodeGrouper
from .models import INGESTIBLE_STATUSES, AnalysisResult, STATUS_NEEDS_REVIEW
from .storage import AnalysisCache, CatalogStore, message_fingerprint

logger = logging.getLogger("animebox.analyzer.batch")

PROGRESS_EVERY = 25


@dataclass
class BatchResult:
    total: int = 0
    processed: int = 0
    from_cache: int = 0
    analyzed: int = 0
    review_needed: int = 0
    new_anime: int = 0
    new_episodes: int = 0
    new_versions: int = 0
    duplicates: int = 0
    failed: int = 0
    groups: list[dict] = field(default_factory=list)
    ungrouped: int = 0

    @property
    def grouped_episodes(self) -> int:
        return len(self.groups)

    def to_dict(self) -> dict:
        return {
            "total": self.total,
            "processed": self.processed,
            "from_cache": self.from_cache,
            "analyzed": self.analyzed,
            "review_needed": self.review_needed,
            "new_anime": self.new_anime,
            "new_episodes": self.new_episodes,
            "new_versions": self.new_versions,
            "duplicates": self.duplicates,
            "failed": self.failed,
            "ungrouped": self.ungrouped,
            "grouped_episodes": len(self.groups),
            "groups": self.groups,
        }


class BatchAnalyzer:
    """Analyse une liste de publications, regroupe et ingère le catalogue."""

    def __init__(
        self,
        analyzer: Analyzer,
        cache: AnalysisCache | None = None,
        store: CatalogStore | None = None,
        ingest: bool = True,
        force: bool = False,
    ):
        self.analyzer = analyzer
        self.cache = cache or AnalysisCache()
        self.store = store or CatalogStore()
        self.ingest = ingest
        self.force = force

    def run(self, messages: list[dict], source: dict | None = None) -> BatchResult:
        result = BatchResult(total=len(messages))
        grouper = EpisodeGrouper()
        channel_id = (source or {}).get("channel_id")
        source_id = (source or {}).get("id")

        for position, message in enumerate(messages, start=1):
            result.processed += 1
            try:
                analysis = self._process_one(message, channel_id, source_id)
                if analysis is None:
                    result.from_cache += 1
                    cached = self.cache.get(channel_id, message.get("message_id"))
                    if cached:
                        analysis = AnalysisResult.from_dict(
                            json_loads_safe(cached["result_json"])
                        )
                        if analysis.status in INGESTIBLE_STATUSES:
                            grouper.add(analysis)
                    continue
                result.analyzed += 1
                if analysis.status == STATUS_NEEDS_REVIEW:
                    result.review_needed += 1
                if analysis.status in INGESTIBLE_STATUSES:
                    grouper.add(analysis)
                    if self.ingest:
                        self._ingest(analysis, result, source_id)
                if position % PROGRESS_EVERY == 0:
                    logger.info(
                        "[Analyzer] lot : %s/%s publications traitées",
                        position,
                        result.total,
                    )
            except Exception:  # noqa: BLE001 - une erreur ne bloque pas le lot
                result.failed += 1
                logger.exception(
                    "[Analyzer] publication %s en erreur (ignorée)",
                    message.get("message_id"),
                )

        result.duplicates += grouper.duplicates
        result.ungrouped = len(grouper.ungrouped)
        result.groups = grouper.to_dict()
        logger.info(
            "[Analyzer] lot terminé : %s traités, %s depuis le cache, "
            "%s épisodes regroupés, %s nouvelles versions, %s doublons, "
            "%s à revoir",
            result.processed,
            result.from_cache,
            len(result.groups),
            result.new_versions,
            result.duplicates,
            result.review_needed,
        )
        return result

    # ------------------------------------------------------------- internes

    def _process_one(
        self, message: dict, channel_id, source_id: str | None
    ) -> AnalysisResult | None:
        """Analyse avec cache ; None = résultat servi depuis le cache."""
        message_id = message.get("message_id")
        fingerprint = message_fingerprint(message)
        if not self.force and message_id is not None:
            cached = self.cache.get(channel_id, message_id)
            if cached is not None and cached.get("fingerprint") == fingerprint:
                logger.info(
                    "[Analyzer] message %s inchangé → cache", message_id
                )
                return None
        analysis = self.analyzer.analyze(message, {"source_id": source_id})
        if message_id is not None:
            self.cache.put(channel_id, message_id, fingerprint, analysis.to_dict())
        return analysis

    def _ingest(
        self, analysis: AnalysisResult, result: BatchResult, source_id: str | None
    ) -> None:
        if not analysis.title_key and not analysis.anime_key:
            return
        anime_key = analysis.anime_key or analysis.title_key
        display = analysis.title or analysis.anime_key or analysis.title_key
        anime, created = self.store.find_or_create_anime(anime_key, display)
        if created:
            result.new_anime += 1
        season_number = analysis.season if analysis.season is not None else 0
        season = self.store.find_or_create_season(anime["id"], season_number)
        if analysis.episode_kind == "special":
            episode, episode_created = self.store.find_or_create_episode(
                season["id"], 0, "special", analysis.title
            )
        else:
            episode, episode_created = self.store.find_or_create_episode(
                season["id"],
                analysis.episode if analysis.episode is not None else 0,
                "regular",
                None,
            )
        if episode_created:
            result.new_episodes += 1
        # Seules les publications média portent une version ; un texte seul
        # (« Épisode 08 disponible ») n'est PAS une vidéo.
        if analysis.media_type in ("video", "document", "audio"):
            outcome = self.store.upsert_version(episode["id"], analysis)
            if outcome == "created":
                result.new_versions += 1
        elif analysis.media_type == "image" and analysis.quality is not None:
            outcome = self.store.upsert_version(episode["id"], analysis)
            if outcome == "created":
                result.new_versions += 1


def json_loads_safe(payload: str):
    import json

    try:
        return json.loads(payload)
    except (TypeError, ValueError):
        return {}
