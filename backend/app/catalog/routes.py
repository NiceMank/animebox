"""Routes HTTP du catalogue enrichi (étape 6).

    GET  /api/catalog/anime                     — liste paginée + recherche par filtre
    GET  /api/catalog/search?q=                 — recherche titre/original/alternatif/alias
    GET  /api/catalog/recent?limit=             — derniers épisodes alimentés (accueil)
    GET  /api/catalog/anime/{id}                — fiche enrichie (saisons → épisodes → versions)
    POST /api/catalog/anime/{id}/refresh-metadata— mise à jour forcée des métadonnées
    PATCH /api/catalog/anime/{id}               — correction manuelle (administration)
    GET  /api/catalog/duplicates                — fiches suspectes (DUPLICATE_REVIEW_REQUIRED)
    POST /api/catalog/duplicates/{id}/resolve   — résolution d'un doublon signalé
    POST /api/catalog/anime/merge               — fusion manuelle de deux fiches
    GET  /api/assets/images/{name}              — images du cache (redimensionnées)

Toutes les routes exigent un jeton Bearer (les images sont publiques :
aucune donnée sensible n'y figure).
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from .. import config, db
from ..analyzer.storage import CatalogStore
from ..auth import require_auth
from ..errors import ApiError
from ..metadata.images import images_dir, valid_filename
from ..metadata.service import MetadataService, build_providers

logger = logging.getLogger("animebox.catalog.routes")

router = APIRouter(tags=["catalog"])

_metadata_service: MetadataService | None = None


def get_metadata_service() -> MetadataService:
    global _metadata_service  # noqa: PLW0603
    if _metadata_service is None:
        _metadata_service = MetadataService(build_providers())
    return _metadata_service


class UpdateAnimeBody(BaseModel):
    display_title: str | None = Field(None, max_length=200)
    synopsis: str | None = Field(None, max_length=4000)
    genres: list[str] | None = None
    year: int | None = Field(None, ge=1900, le=2100)
    status: str | None = Field(None, max_length=30)
    season_count: int | None = Field(None, ge=0)
    episode_count: int | None = Field(None, ge=0)
    rating: float | None = Field(None, ge=0, le=10)


class MergeBody(BaseModel):
    target_id: int
    source_id: int


class ResolveDuplicateBody(BaseModel):
    resolution: str = Field(pattern="^(resolved_merged|resolved_not_duplicate)$")


def _get_anime_or_404(anime_id: int) -> dict:
    anime = CatalogStore().get_anime_public(anime_id)
    if anime is None:
        raise ApiError("ANIME_NOT_FOUND", "Animé introuvable dans le catalogue.", 404)
    return anime


# ---------------------------------------------------------------------------
# Liste, recherche, récents
# ---------------------------------------------------------------------------


@router.get("/api/catalog/anime", dependencies=[Depends(require_auth)])
def catalog_anime(offset: int = 0, limit: int = 50, query: str = "") -> dict:
    limit = min(max(limit, 1), 200)
    offset = max(offset, 0)
    store = CatalogStore()
    if query.strip():
        results = store.search_anime(query, limit=limit, offset=offset)
        return {"anime": results, "total": len(results), "query": query.strip()}
    return {
        "anime": store.list_anime(offset=offset, limit=limit),
        "total": store.count_anime(),
    }


@router.get("/api/catalog/search", dependencies=[Depends(require_auth)])
def catalog_search(q: str = "", limit: int = 25, offset: int = 0) -> dict:
    limit = min(max(limit, 1), 100)
    offset = max(offset, 0)
    store = CatalogStore()
    results = store.search_anime(q, limit=limit, offset=offset)
    return {"results": results, "total": len(results), "query": q}


@router.get("/api/catalog/recent", dependencies=[Depends(require_auth)])
def catalog_recent(limit: int = 20) -> dict:
    limit = min(max(limit, 1), 100)
    return {"recent": CatalogStore().recent_episodes(limit=limit)}


# ---------------------------------------------------------------------------
# Fiche enrichie + métadonnées
# ---------------------------------------------------------------------------


@router.get("/api/catalog/anime/{anime_id}", dependencies=[Depends(require_auth)])
def catalog_anime_detail(anime_id: int) -> dict:
    store = CatalogStore()
    anime = _get_anime_or_404(anime_id)
    # Enrichissement paresseux : première consultation ou cache expiré.
    anime = get_metadata_service().ensure_enriched(anime)
    detail = store.anime_detail(anime_id)
    if detail is None:
        raise ApiError("ANIME_NOT_FOUND", "Animé introuvable dans le catalogue.", 404)
    # Le détail embarque déjà les champs de métadonnées (sérialiseur public).
    for season in detail["seasons"]:
        for episode in season["episodes"]:
            episode["best_version"] = store.best_version(episode["versions"])
            episode["version_count"] = len(episode["versions"])
    return {"anime": detail}


@router.post(
    "/api/catalog/anime/{anime_id}/refresh-metadata",
    dependencies=[Depends(require_auth)],
)
def refresh_metadata(anime_id: int) -> dict:
    store = CatalogStore()
    anime = _get_anime_or_404(anime_id)
    updated = get_metadata_service().enrich(anime, force=True)
    return {"anime": updated}


@router.patch("/api/catalog/anime/{anime_id}", dependencies=[Depends(require_auth)])
def update_anime(anime_id: int, body: UpdateAnimeBody) -> dict:
    """Correction manuelle (administration) : fige l'enrichissement auto.

    Après une édition manuelle, le service ne remplace plus les valeurs
    (sauf rafraîchissement forcé) ; le contenu Telegram n'est jamais perdu.
    """
    store = CatalogStore()
    _get_anime_or_404(anime_id)
    fields = {
        key: value
        for key, value in body.model_dump().items()
        if value is not None
    }
    fields["manually_edited"] = True
    fields["metadata_updated_at"] = datetime.now(timezone.utc).isoformat()
    updated = store.update_anime_metadata(anime_id, fields)
    logger.info("[Catalogue] édition manuelle de la fiche %s", anime_id)
    return {"anime": updated}


# ---------------------------------------------------------------------------
# Doublons de fiches (jamais fusionnés automatiquement)
# ---------------------------------------------------------------------------


@router.get("/api/catalog/duplicates", dependencies=[Depends(require_auth)])
def catalog_duplicates(status: str = "review_required") -> dict:
    return {"duplicates": CatalogStore().list_duplicates(status=status)}


@router.post("/api/catalog/duplicates/{duplicate_id}/resolve", dependencies=[Depends(require_auth)])
def resolve_duplicate(duplicate_id: int, body: ResolveDuplicateBody) -> dict:
    resolved = CatalogStore().resolve_duplicate(duplicate_id, body.resolution)
    if resolved is None:
        raise ApiError("DUPLICATE_NOT_FOUND", "Signalement de doublon introuvable.", 404)
    return {"duplicate": resolved}


@router.post("/api/catalog/anime/merge", dependencies=[Depends(require_auth)])
def merge_anime(body: MergeBody) -> dict:
    """Fusion manuelle : déplace le contenu de source_id vers target_id."""
    merged = CatalogStore().merge_anime(body.target_id, body.source_id)
    if merged is None:
        raise ApiError(
            "MERGE_FAILED",
            "Fusion impossible : vérifiez que les deux fiches existent et diffèrent.",
            422,
        )
    return {"anime": merged}


# ---------------------------------------------------------------------------
# Correction manuelle (administrateur) — jamais d'association automatique
# ---------------------------------------------------------------------------


class ApplyCandidateBody(BaseModel):
    provider_id: str = Field(min_length=1, max_length=64)
    provider: str | None = Field(None, max_length=32)


class ReassignVersionBody(BaseModel):
    season_number: int | None = Field(None, ge=1, le=99)
    episode_number: int | None = Field(None, ge=0, le=99999)
    anime_id: int | None = None


@router.post("/api/catalog/anime/{anime_id}/apply-candidate", dependencies=[Depends(require_auth)])
def apply_candidate(anime_id: int, body: ApplyCandidateBody) -> dict:
    """Associe explicitement un candidat (décision humaine)."""
    anime = _get_anime_or_404(anime_id)
    updated = get_metadata_service().apply_candidate(anime, body.provider_id, body.provider)
    if updated is None:
        raise ApiError("CANDIDATE_NOT_FOUND", "Candidat introuvable chez les fournisseurs.", 404)
    return {"anime": updated}


@router.post("/api/catalog/anime/{anime_id}/ignore", dependencies=[Depends(require_auth)])
def ignore_anime(anime_id: int) -> dict:
    """Ferme la demande de revue (l'admin garde la fiche telle quelle)."""
    anime = _get_anime_or_404(anime_id)
    return {"anime": get_metadata_service().ignore_anime(anime)}


@router.post("/api/catalog/versions/{version_id}/reassign", dependencies=[Depends(require_auth)])
def reassign_version(version_id: int, body: ReassignVersionBody) -> dict:
    """Déplace une publication vers une autre saison/épisode/animé."""
    from ..analyzer.storage import CatalogStore

    store = CatalogStore()
    updated = store.reassign_version(
        version_id,
        season_number=body.season_number,
        episode_number=body.episode_number,
        anime_id=body.anime_id,
    )
    if updated is None:
        raise ApiError("VERSION_NOT_FOUND", "Publication introuvable.", 404)
    return {"anime": updated}


# ---------------------------------------------------------------------------
# Images du cache (publiques — aucune donnée sensible)
# ---------------------------------------------------------------------------


@router.get("/api/assets/images/{filename}")
def catalog_image(filename: str, authorization: str | None = Header(default=None)) -> FileResponse:
    # Vérification de session optionnelle : les images restent publiques pour
    # être affichables par le client mobile sans en-tête particulier.
    if not valid_filename(filename):
        raise ApiError("INVALID_INPUT", "Nom d'image invalide.", 422)
    from pathlib import Path

    path = Path(images_dir()) / filename
    if not path.exists():
        raise ApiError("IMAGE_NOT_FOUND", "Image introuvable.", 404)
    return FileResponse(
        path,
        media_type="image/jpeg",
        headers={"Cache-Control": "public, max-age=604800, immutable"},
    )
