"""Fournisseur distant : Jikan (API publique REST de MyAnimeList).

- API publique et documentée : https://jikan.moe — aucune clé requise,
  aucune authentification, aucune donnée privée.
- Respect du service : limitation de débit (intervalle minimal entre
  requêtes), délai d'attente, aucune technique de contournement.
- Jamais de scrapping agressif : uniquement les endpoints de l'API.
"""

from __future__ import annotations

import threading
import time

import httpx

from .. import config
from .base import MetadataAnime, MetadataCandidate, MetadataEpisode, MetadataProvider, MetadataSeason, ProviderError

_MIN_INTERVAL = 0.4  # Jikan : ~3 requêtes/seconde par IP ; on reste prudent.
_REQUEST_LOCK = threading.Lock()
_LAST_REQUEST = 0.0

_ALLOWED_IMAGE_HOSTS = {"cdn.myanimelist.net", "image.tmdb.org"}


def _throttle() -> None:
    global _LAST_REQUEST  # noqa: PLW0603
    with _REQUEST_LOCK:
        wait = _MIN_INTERVAL - (time.monotonic() - _LAST_REQUEST)
        if wait > 0:
            time.sleep(wait)
        _LAST_REQUEST = time.monotonic()


def _text(value) -> str | None:
    return (value or "").strip() or None


class JikanProvider(MetadataProvider):
    """Récupération distante via Jikan (aucune clé d'API)."""

    name = "jikan"

    def __init__(self, base_url: str | None = None, timeout: float | None = None):
        self._base = (base_url or config.METADATA_REMOTE_BASE_URL).rstrip("/")
        self._timeout = timeout or config.METADATA_TIMEOUT_SECONDS

    # ------------------------------------------------------------------ API

    def search(self, title: str, limit: int = 5) -> list[MetadataCandidate]:
        params = {"q": title, "limit": limit, "sfw": "true"}
        payload = self._get("/anime", params=params)
        data = (payload or {}).get("data") or []
        return [self._candidate(item) for item in data]

    def fetch(self, provider_id: str) -> MetadataAnime | None:
        payload = self._get(f"/anime/{provider_id}/full")
        data = (payload or {}).get("data")
        if not data:
            return None
        return self._anime(data)

    def fetch_episodes(self, provider_id: str) -> tuple[MetadataEpisode, ...]:
        # Première page uniquement : évite les rafales de requêtes ; les
        # épisodes plus lointains peuvent être complétés plus tard.
        payload = self._get(f"/anime/{provider_id}/episodes", params={"page": 1})
        data = (payload or {}).get("data") or []
        episodes: list[MetadataEpisode] = []
        for item in data:
            try:
                number = int(item.get("mal_id") or item.get("episode") or -1)
            except (TypeError, ValueError):
                number = -1
            if number <= 0:
                continue
            episodes.append(
                MetadataEpisode(
                    number=number,
                    title=_text(item.get("title")),
                    synopsis=None,
                    air_date=_text(item.get("aired")),
                )
            )
        return tuple(episodes)

    # ----------------------------------------------------------- internes

    def _get(self, path: str, params: dict | None = None) -> dict | None:
        _throttle()
        try:
            response = httpx.get(
                f"{self._base}{path}",
                params=params,
                timeout=self._timeout,
                headers={"User-Agent": "AnimeBox/0.6 (catalog enrichment)"},
            )
        except httpx.HTTPError as error:
            raise ProviderError(f"Jikan injoignable : {type(error).__name__}") from error
        if response.status_code == 429:
            raise ProviderError("Jikan : limite de débit atteinte.")
        if response.status_code >= 400:
            raise ProviderError(f"Jikan : HTTP {response.status_code}.")
        try:
            return response.json()
        except ValueError as error:
            raise ProviderError("Jikan : réponse illisible.") from error

    @staticmethod
    def _image(item: dict, field: str) -> str | None:
        images = item.get("images") or {}
        value = images.get(field) or {}
        url = value.get("image_url") or value.get("large_image_url")
        if not url:
            return None
        host = url.split("/")[2] if url.startswith(("http://", "https://")) and "/" in url[8:] else ""
        return url if host in _ALLOWED_IMAGE_HOSTS else None

    @staticmethod
    def _genres(item: dict) -> tuple[str, ...]:
        return tuple(
            entry.get("name") for entry in (item.get("genres") or []) if entry.get("name")
        )

    @classmethod
    def _candidate(cls, item: dict) -> MetadataCandidate:
        return MetadataCandidate(
            provider="jikan",
            provider_id=str(item.get("mal_id") or ""),
            title=item.get("title") or "",
            original_title=_text(item.get("title_japanese")),
            alternative_titles=tuple(
                title
                for title in [
                    _text(item.get("title_english")),
                    *[entry.get("title") for entry in (item.get("title_synonyms") or [])],
                ]
                if title
            ),
            year=item.get("year"),
            season_count=None,
            episode_count=item.get("episodes"),
            genres=cls._genres(item),
            synopsis=_text(item.get("synopsis")),
            status=_text(item.get("status")),
            rating=(item.get("score") or None),
            poster_url=cls._image(item, "jpg"),
            backdrop_url=cls._image(item, "jpg"),
        )

    @classmethod
    def _anime(cls, item: dict) -> MetadataAnime:
        seasons: list[MetadataSeason] = []
        if item.get("season") and item.get("year"):
            seasons.append(
                MetadataSeason(
                    number=1,
                    title=f"{item['season']} {item['year']}",
                    year=item.get("year"),
                    episode_count=item.get("episodes"),
                )
            )
        return MetadataAnime(
            provider="jikan",
            provider_id=str(item.get("mal_id") or ""),
            canonical_title=item.get("title") or "",
            original_title=_text(item.get("title_japanese")),
            alternative_titles=tuple(
                title
                for title in [
                    _text(item.get("title_english")),
                    *[entry.get("title") for entry in (item.get("title_synonyms") or [])],
                ]
                if title
            ),
            synopsis=_text(item.get("synopsis")),
            genres=cls._genres(item),
            year=item.get("year"),
            status=_text(item.get("status")),
            season_count=None,
            episode_count=item.get("episodes"),
            rating=(item.get("score") or None),
            duration_min=_text(item.get("duration")),
            poster_url=cls._image(item, "jpg"),
            backdrop_url=cls._image(item, "jpg"),
            seasons=tuple(seasons),
        )
