"""Service d'enrichissement : orchestrer les fournisseurs, mettre en cache,
associer (ou pas) et conserver les états de revue.

Flux typique quand un animé est détecté :

    animé détecté (Solo Leveling)
        → recherche des candidats chez les fournisseurs (ordre configuré)
        → score de correspondance (matching.py)
            ≥ 85 %  → association automatique + fiche complète
            55–85 % → statut METADATA_REVIEW_REQUIRED (candidats conservés)
            < 55 %  → statut NOT_FOUND → fiche minimale « Informations en attente »

La mise à jour est pilotée par `metadataUpdatedAt` + une durée de cache
configurable (METADATA_TTL_DAYS) : pas de récupération à chaque affichage.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from .. import config
from ..analyzer.storage import CatalogStore
from .base import MetadataAnime, MetadataCandidate, MetadataProvider, ProviderError
from .images import cache_and_resize
from .local import LocalMetadataProvider
from .matching import classify_match, score_candidate

logger = logging.getLogger("animebox.metadata.service")

STATUS_PENDING = "pending"  # pas encore recherché
STATUS_FOUND = "found"  # associé avec confiance
STATUS_NOT_FOUND = "not_found"  # rien de fiable → fiche minimale
STATUS_REVIEW_REQUIRED = "review_required"  # correspondance incertaine
STATUS_IGNORED = "ignored"  # correction manuelle : ne plus proposer de revue

# Statuts considérés comme « traités » (pas de ré-enrichissement automatique).
SETTLED_STATUSES = (STATUS_FOUND, STATUS_NOT_FOUND, STATUS_REVIEW_REQUIRED, STATUS_IGNORED)


def build_providers() -> list[MetadataProvider]:
    """Fournisseurs actifs selon la configuration (voir config.py)."""
    choice = config.METADATA_PROVIDER
    if choice == "none":
        return []
    if choice == "local":
        return [LocalMetadataProvider()]
    if choice == "jikan":
        from .jikan import JikanProvider

        return [JikanProvider(), LocalMetadataProvider()]
    # « auto » : distant en mode réel, local en mode simulation/tests.
    if config.MOCK_MODE:
        return [LocalMetadataProvider()]
    from .jikan import JikanProvider

    return [JikanProvider(), LocalMetadataProvider()]


class MetadataService:
    """Enrichissement du catalogue avec cache (SQLite) et stratégie de repli."""

    def __init__(self, providers: list[MetadataProvider] | None = None):
        self.providers = providers if providers is not None else build_providers()
        self.store = CatalogStore()

    @property
    def ttl(self) -> timedelta:
        return timedelta(days=config.METADATA_TTL_DAYS)

    def _fresh(self, anime: dict) -> bool:
        updated = anime.get("metadata_updated_at")
        if not updated:
            return False
        try:
            stamp = datetime.fromisoformat(updated)
        except ValueError:
            return False
        return datetime.now(timezone.utc) - stamp < self.ttl

    # ------------------------------------------------------------------ API

    def ensure_enriched(self, anime: dict, force: bool = False) -> dict:
        """Enrichit si nécessaire (première vue ou cache expiré)."""
        status = anime.get("metadata_status") or STATUS_PENDING
        if not force and status in SETTLED_STATUSES and self._fresh(anime):
            return anime
        return self.enrich(anime, force=force)

    def enrich(self, anime: dict, force: bool = False) -> dict:
        """Recherche et associe les métadonnées d'un animé."""
        if anime.get("manually_edited") and not force:
            logger.info("[Métadonnées] %s : édition manuelle — enrichissement sauté", anime["key"])
            return anime

        query = anime.get("display_title") or anime["canonical_title"]
        if not query:
            return anime

        candidates = self._candidates(query)
        best_candidate, confidence = self._best_of(candidates, query, anime)
        fields: dict = {
            "metadata_updated_at": datetime.now(timezone.utc).isoformat(),
        }
        if best_candidate is None:
            fields.update(
                metadata_status=STATUS_NOT_FOUND,
                metadata_source=self.providers[0].name if self.providers else None,
                metadata_confidence=0.0,
            )
            self.store.update_anime_metadata(anime["id"], fields)
            logger.info("[Métadonnées] %s : introuvable → fiche minimale", query)
            return self.store.get_anime_public(anime["id"])  # type: ignore[return-value]

        if classify_match(confidence) == "review":
            review_candidates = [
                {"provider_id": c.provider_id, "title": c.title, "year": c.year, "score": c.similarity}
                for c in candidates[:3]
            ]
            fields.update(
                metadata_status=STATUS_REVIEW_REQUIRED,
                metadata_source=best_candidate.provider,
                metadata_confidence=confidence,
                metadata_candidates=review_candidates,
            )
            self.store.update_anime_metadata(anime["id"], fields)
            logger.info("[Métadonnées] %s : correspondance incertaine (%s%%) → revue requise", query, round(confidence * 100))
            return self.store.get_anime_public(anime["id"])  # type: ignore[return-value]

        return self._apply(anime, best_candidate, confidence)

    def _apply(self, anime: dict, candidate: MetadataCandidate, confidence: float) -> dict:
        provider = next((p for p in self.providers if p.name == candidate.provider), None)
        details: MetadataAnime | None = None
        if provider is not None:
            try:
                details = provider.fetch(candidate.provider_id)
            except ProviderError as error:
                logger.warning("[Métadonnées] fiche %s indisponible (%s)", candidate.provider_id, error)
        if details is None:
            details = MetadataAnime(
                provider=candidate.provider,
                provider_id=candidate.provider_id,
                canonical_title=candidate.title,
                original_title=candidate.original_title,
                alternative_titles=candidate.alternative_titles,
                synopsis=candidate.synopsis,
                genres=candidate.genres,
                year=candidate.year,
                status=candidate.status,
                season_count=candidate.season_count,
                episode_count=candidate.episode_count,
                rating=candidate.rating,
                poster_url=candidate.poster_url,
                backdrop_url=candidate.backdrop_url,
            )

        # Images : téléchargées et mises en cache par le backend (tailles
        # adaptées) — aucune grosse ressource n'est renvoyée au mobile.
        poster_file = None
        backdrop_file = None
        if config.METADATA_DOWNLOAD_IMAGES:
            if details.poster_url:
                poster_file = cache_and_resize(details.poster_url, "poster")
            if details.backdrop_url:
                backdrop_file = cache_and_resize(details.backdrop_url, "backdrop")
        poster_url = f"/api/assets/images/{poster_file}" if poster_file else None
        backdrop_url = f"/api/assets/images/{backdrop_file}" if backdrop_file else None

        fields = {
            "display_title": details.canonical_title,
            "original_title": details.original_title,
            "alternative_titles": list(details.alternative_titles),
            "synopsis": details.synopsis,
            "genres": list(details.genres),
            "year": details.year,
            "status": details.status,
            "season_count": details.season_count,
            "episode_count": details.episode_count,
            "rating": details.rating,
            "duration_min": details.duration_min,
            "poster_url": poster_url,
            "backdrop_url": backdrop_url,
            "poster_asset": details.poster_asset,
            "backdrop_asset": details.backdrop_asset,
            "metadata_source": details.provider,
            "metadata_status": STATUS_FOUND,
            "metadata_provider_id": details.provider_id,
            "metadata_confidence": confidence,
            "metadata_candidates": [],
            "metadata_updated_at": datetime.now(timezone.utc).isoformat(),
        }
        self.store.update_anime_metadata(anime["id"], fields)

        # Titres d'épisodes officiels (jamais inventés : None si absents).
        if provider is not None and details.provider != "local":
            try:
                episodes = provider.fetch_episodes(candidate.provider_id)
            except ProviderError:
                episodes = ()
            self._fill_episode_titles(anime["id"], episodes)

        # Doublon potentiel : un autre animé déjà associé au même identifiant
        # fournisseur → revue requise (jamais de fusion automatique).
        self._flag_same_provider_id(anime["id"], details.provider, details.provider_id)

        logger.info(
            "[Métadonnées] %s → %s (%s, %s%%) : fiche enrichie",
            anime["key"],
            details.canonical_title,
            details.provider,
            round(confidence * 100),
        )
        return self.store.get_anime_public(anime["id"])  # type: ignore[return-value]

    def _best_of(
        self, candidates: list[MetadataCandidate], query: str, anime: dict
    ) -> tuple[MetadataCandidate | None, float]:
        known_year = anime.get("release_year") or anime.get("year")
        best: tuple[MetadataCandidate | None, float] = (None, 0.0)
        for candidate in candidates:
            score = score_candidate(query, candidate, known_year)
            if score > best[1]:
                best = (candidate, score)
        return best

    def _candidates(self, query: str) -> list[MetadataCandidate]:
        seen: set[str] = set()
        results: list[MetadataCandidate] = []
        for provider in self.providers:
            try:
                found = provider.search(query)
            except ProviderError as error:
                logger.warning("[Métadonnées] fournisseur %s indisponible : %s", provider.name, error)
                continue
            except Exception:  # noqa: BLE001 - un fournisseur défaillant ne bloque pas les autres
                logger.exception("[Métadonnées] fournisseur %s en erreur (ignoré)", provider.name)
                continue
            for candidate in found:
                key = f"{candidate.provider}:{candidate.provider_id}"
                if key not in seen:
                    seen.add(key)
                    results.append(candidate)
        return results

    def _fill_episode_titles(self, anime_id: int, episodes) -> None:
        if not episodes:
            return
        # Remplit les titres manquants (ne touche jamais aux titres existants).
        detail = self.store.anime_detail(anime_id)
        if detail is None:
            return
        by_number = {episode.number: episode for episode in episodes if episode.title}
        from ..analyzer import storage

        with storage._lock, storage._connect() as connection:  # noqa: SLF001
            for season in detail["seasons"]:
                for episode in season["episodes"]:
                    if episode.get("title"):
                        continue
                    match = by_number.get(episode["number"])
                    if match is not None:
                        connection.execute(
                            "UPDATE episode SET title = ? WHERE id = ?",
                            (match.title, episode["id"]),
                        )

    def _flag_same_provider_id(self, anime_id: int, provider: str, provider_id: str) -> None:
        if not provider_id:
            return
        from ..analyzer import storage

        for other in self.store.list_anime():
            if other["id"] == anime_id or other.get("metadata_source") != provider:
                continue
            with storage._connect() as connection:  # noqa: SLF001
                row = connection.execute(
                    "SELECT metadata_provider_id FROM anime WHERE id = ?", (other["id"],)
                ).fetchone()
            if row and row["metadata_provider_id"] == provider_id:
                self.store.add_duplicate(anime_id, other["id"], "same_provider_id", 1.0)

    # ------------------------------------------------------------- Admin

    def apply_candidate(self, anime: dict, provider_id: str, provider: str | None = None) -> dict | None:
        """Correction manuelle (admin) : associe EXPLICITEMENT un candidat.

        L'association n'est jamais faite aveuglément : elle vient d'une
        décision humaine, puis la fiche est gelée (manually_edited).
        """
        details: MetadataAnime | None = None
        candidates = [p for p in self.providers if provider is None or p.name == provider]
        for candidate_provider in candidates:
            try:
                details = candidate_provider.fetch(provider_id)
            except ProviderError as error:
                logger.warning("[Métadonnées] fiche %s indisponible (%s)", provider_id, error)
                continue
            if details is not None:
                break
        if details is None:
            return None
        candidate = MetadataCandidate(
            provider=details.provider,
            provider_id=details.provider_id,
            title=details.canonical_title,
            original_title=details.original_title,
            alternative_titles=details.alternative_titles,
            year=details.year,
            season_count=details.season_count,
            episode_count=details.episode_count,
            genres=details.genres,
            synopsis=details.synopsis,
            status=details.status,
            rating=details.rating,
            poster_url=details.poster_url,
            backdrop_url=details.backdrop_url,
        )
        enriched = self._apply(anime, candidate, 1.0)
        # L'administrateur assume cette association : l'enrichissement
        # automatique ne la remplacera plus (le forçage reste possible).
        self.store.update_anime_metadata(anime["id"], {"manually_edited": True})
        logger.info("[Métadonnées] admin : %s associé à %s", anime["key"], details.canonical_title)
        return self.store.get_anime_public(anime["id"])

    def ignore_anime(self, anime: dict) -> dict:
        """Correction manuelle (admin) : ignorer — plus de proposition de revue."""
        updated = self.store.update_anime_metadata(
            anime["id"],
            {"metadata_status": STATUS_IGNORED, "manually_edited": True},
        )
        logger.info("[Métadonnées] admin : %s ignoré (revue fermée)", anime["key"])
        return updated or anime
