"""Routes HTTP du moteur d'analyse.

    GET  /analyzer/status                 — état du moteur, cache, catalogue
    POST /analyzer/analyze                — analyse d'une publication
    POST /analyzer/analyze-batch          — analyse d'un lot (≤ 500)
    POST /analyzer/group                  — regroupement d'analyses fournies
    POST /api/sources/{id}/analyze        — analyse d'une source (tâche de fond)
    GET  /analyzer/jobs/{job_id}          — avancement d'une tâche
    GET  /api/catalog/anime               — catalogue (données pour l'app)
    GET  /api/catalog/anime/{anime_id}    — détail anime → saisons → épisodes → versions

Toutes les routes exigent un jeton Bearer valide. L'analyse ne porte que sur
les publications auxquelles le compte connecté a légitimement accès (elles
proviennent du gateway Telegram du backend).
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel, Field

from . import db
from .analyzer.aliases import AliasRegistry, AnimeTitle
from .analyzer.batch import BatchAnalyzer, BatchResult
from .analyzer.engine import RuleBasedAnalyzer
from .analyzer.grouping import EpisodeGrouper
from .analyzer.models import AnalysisResult
from .analyzer.quality import QUALITY_SPECS
from .analyzer.storage import AnalysisCache, CatalogStore, JobStore, init_schema
from .auth import require_auth
from .errors import ApiError, not_connected

logger = logging.getLogger("animebox.analyzer.routes")

router = APIRouter(tags=["analyzer"])

_engine: RuleBasedAnalyzer | None = None
_gateway = None


def init(gateway) -> None:
    """Appelé au démarrage : construit le moteur et le registre de titres.

    Le registre combine le catalogue intégré et les alias enregistrés en
    base (personnalisables sans redémarrage via add_alias).
    """
    global _engine, _gateway
    _gateway = gateway
    init_schema()
    registry = AliasRegistry()
    store = CatalogStore()
    for anime in store.list_anime():
        title = AnimeTitle(
            key=anime["key"],
            title=anime["title"],
            original_title=anime.get("original_title"),
            release_year=anime.get("release_year"),
        )
        registry.register(title)
    for alias_row in store.list_aliases():
        canonical = registry.resolve_exact(alias_row["anime_key"])
        if canonical is not None:
            registry.register_aliases(canonical, (alias_row["alias_key"],))
    _engine = RuleBasedAnalyzer(registry=registry)
    logger.info("[Analyzer] moteur initialisé (%s, registre : %s titres)", _engine.version, len(registry))


def _engine_or_fail() -> RuleBasedAnalyzer:
    if _engine is None:
        raise ApiError("ANALYZER_NOT_READY", "Moteur d'analyse non initialisé.", 500)
    return _engine


# ---------------------------------------------------------------------------
# Corps de requêtes
# ---------------------------------------------------------------------------


class AnalyzeBody(BaseModel):
    text: str | None = Field(None, max_length=2000)
    file_name: str | None = Field(None, max_length=500)
    mime_type: str | None = None
    file_size: int | None = Field(None, ge=0)
    duration: int | None = Field(None, ge=0)
    width: int | None = Field(None, ge=0)
    height: int | None = Field(None, ge=0)
    media_type: str | None = None
    telegram_channel_id: str | None = None
    telegram_channel_username: str | None = None
    telegram_message_id: int | None = None
    telegram_message_link: str | None = None


class AnalyzeBatchBody(BaseModel):
    messages: list[AnalyzeBody] = Field(min_length=1, max_length=500)
    group: bool = True


class GroupBody(BaseModel):
    analyses: list[dict] = Field(min_length=1, max_length=500)


class SourceAnalyzeBody(BaseModel):
    limit: int = Field(200, ge=1, le=500)
    force: bool = False


# ---------------------------------------------------------------------------
# État du moteur
# ---------------------------------------------------------------------------


@router.get("/analyzer/status", dependencies=[Depends(require_auth)])
def analyzer_status() -> dict:
    from . import config

    engine = _engine_or_fail()
    return {
        "engine": {"name": engine.name, "version": engine.version, "external_ai": False},
        "mode": "mock" if config.MOCK_MODE else "telegram",
        "catalog": CatalogStore().counts(),
        "cache": AnalysisCache().stats(),
        "jobs_running": JobStore().running_count(),
        "supported_qualities": [spec.canonical for spec in QUALITY_SPECS],
        "season_formats": ["S02E08", "S2 E8", "2x08", "Season 2", "Saison 2 Episode 8"],
        "episode_formats": ["E01", "EP01", "Episode 01", "Épisode 01", "numéro seul (titre connu)"],
    }


# ---------------------------------------------------------------------------
# Analyse unitaire / par lot / regroupement
# ---------------------------------------------------------------------------


@router.post("/analyzer/analyze", dependencies=[Depends(require_auth)])
def analyze_one(body: AnalyzeBody) -> dict:
    engine = _engine_or_fail()
    result = engine.analyze(body.model_dump())
    return {"analysis": result.to_dict()}


@router.post("/analyzer/analyze-batch", dependencies=[Depends(require_auth)])
def analyze_batch(body: AnalyzeBatchBody) -> dict:
    engine = _engine_or_fail()
    grouper = EpisodeGrouper()
    analyses: list[dict] = []
    review_needed = 0
    for message in body.messages:
        result = engine.analyze(message.model_dump())
        analyses.append(result.to_dict())
        if result.status == "needs_review":
            review_needed += 1
        grouper.add(result)
    response: dict = {
        "count": len(analyses),
        "review_needed": review_needed,
        "duplicates": grouper.duplicates,
        "results": analyses,
    }
    if body.group:
        response["groups"] = grouper.to_dict()
    return response


@router.post("/analyzer/group", dependencies=[Depends(require_auth)])
def group_analyses(body: GroupBody) -> dict:
    grouper = EpisodeGrouper()
    for payload in body.analyses:
        grouper.add(AnalysisResult.from_dict(payload))
    return {
        "groups": grouper.to_dict(),
        "grouped_episodes": len(grouper),
        "duplicates": grouper.duplicates,
        "ungrouped": len(grouper.ungrouped),
    }


# ---------------------------------------------------------------------------
# Analyse d'une source (tâche de fond) + suivi des travaux
# ---------------------------------------------------------------------------


def _run_analysis_job(job_id: str, source: dict, limit: int, force: bool) -> None:
    jobs = JobStore()
    try:
        if not _gateway.is_connected():
            raise not_connected()
        messages = _gateway.fetch_messages(source["username"], source.get("channel_id"), limit)
        for message in messages:
            message.setdefault("telegram_channel_id", source.get("channel_id"))
            message.setdefault("telegram_channel_username", source["username"])
        db.upsert_messages(source["id"], messages)
        jobs.update(job_id, total=len(messages))
        batch = BatchAnalyzer(
            _engine_or_fail(),
            cache=AnalysisCache(),
            store=CatalogStore(),
            ingest=True,
            force=force,
        )
        result = batch.run(messages, source=source)
        anime_keys = {group["anime"]["key"] for group in result.groups}
        db.update_source(
            source["id"],
            analyzed_posts=result.processed,
            detected_anime=len(anime_keys),
            detected_episodes=result.new_episodes,
        )
        stats = db.get_stats()
        db.set_stats(
            analyzed_posts=stats["analyzed_posts"] + result.processed,
            detected_anime=stats["detected_anime"] + len(anime_keys),
            detected_episodes=stats["detected_episodes"] + result.new_episodes,
            new_episodes=result.new_episodes,
            duplicates_grouped=result.duplicates,
        )
        jobs.update(
            job_id,
            status="done",
            processed=result.processed,
            from_cache=result.from_cache,
            new_episodes=result.new_episodes,
            new_versions=result.new_versions,
            duplicates=result.duplicates,
            review_needed=result.review_needed,
            finished_at=datetime.now(timezone.utc).isoformat(),
        )
        logger.info("[Analyzer] tâche %s terminée pour la source %s", job_id, source["username"])
    except ApiError as error:
        jobs.update(job_id, status="error", error=error.message)
        logger.warning("[Analyzer] tâche %s en erreur : %s", job_id, error.code)
    except Exception:  # noqa: BLE001 - jamais de trace technique vers le client
        logger.exception("[Analyzer] tâche %s en erreur interne", job_id)
        jobs.update(job_id, status="error", error="Erreur interne d'analyse.")


@router.post("/api/sources/{source_id}/analyze", dependencies=[Depends(require_auth)], status_code=202)
def analyze_source(
    source_id: str, background: BackgroundTasks, body: SourceAnalyzeBody | None = None
) -> dict:
    source = db.get_source(source_id)
    if source is None:
        raise ApiError("SOURCE_NOT_FOUND", "Source introuvable.", 404)
    if not _gateway.is_connected():
        raise not_connected()
    limit = body.limit if body else 200
    force = body.force if body else False
    job_id = uuid.uuid4().hex
    JobStore().create(job_id, source_id, total=0)
    background.add_task(_run_analysis_job, job_id, source, limit, force)
    return {"job_id": job_id, "status": "running"}


@router.get("/analyzer/jobs/{job_id}", dependencies=[Depends(require_auth)])
def analyzer_job(job_id: str) -> dict:
    job = JobStore().get(job_id)
    if job is None:
        raise ApiError("JOB_NOT_FOUND", "Tâche d'analyse introuvable.", 404)
    return {"job": job}


# ---------------------------------------------------------------------------
# Catalogue (préparation des données pour l'application mobile)
# ---------------------------------------------------------------------------


@router.get("/api/catalog/anime", dependencies=[Depends(require_auth)])
def catalog_anime() -> dict:
    return {"anime": CatalogStore().list_anime()}


@router.get("/api/catalog/anime/{anime_id}", dependencies=[Depends(require_auth)])
def catalog_anime_detail(anime_id: int) -> dict:
    detail = CatalogStore().anime_detail(anime_id)
    if detail is None:
        raise ApiError("ANIME_NOT_FOUND", "Animé introuvable dans le catalogue.", 404)
    return {"anime": detail}
