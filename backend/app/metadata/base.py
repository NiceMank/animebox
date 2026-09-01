"""Contrats du système de métadonnées.

`MetadataProvider` est l'abstraction commune : ajouter un fournisseur (API
officielle, base locale…) ne change rien au reste du pipeline.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


class ProviderError(Exception):
    """Erreur de fournisseur (réseau, quota, indisponibilité) — jamais fatale."""


@dataclass
class MetadataSeason:
    number: int
    title: str | None = None
    year: int | None = None
    episode_count: int | None = None


@dataclass
class MetadataEpisode:
    number: int
    title: str | None = None
    synopsis: str | None = None
    air_date: str | None = None
    thumbnail: str | None = None


@dataclass
class MetadataAnime:
    """Fiche complète renvoyée par un fournisseur."""

    provider: str
    provider_id: str
    canonical_title: str
    original_title: str | None = None
    alternative_titles: tuple[str, ...] = ()
    synopsis: str | None = None
    genres: tuple[str, ...] = ()
    year: int | None = None
    status: str | None = None
    season_count: int | None = None
    episode_count: int | None = None
    rating: float | None = None
    duration_min: int | None = None
    poster_url: str | None = None
    backdrop_url: str | None = None
    poster_asset: str | None = None
    backdrop_asset: str | None = None
    seasons: tuple[MetadataSeason, ...] = ()
    episodes: tuple[MetadataEpisode, ...] = ()

    @property
    def all_titles(self) -> tuple[str, ...]:
        return (self.canonical_title, self.original_title, *self.alternative_titles)


@dataclass
class MetadataCandidate:
    """Candidat renvoyé par une recherche de métadonnées."""

    provider: str
    provider_id: str
    title: str
    original_title: str | None = None
    alternative_titles: tuple[str, ...] = ()
    year: int | None = None
    season_count: int | None = None
    episode_count: int | None = None
    genres: tuple[str, ...] = ()
    synopsis: str | None = None
    status: str | None = None
    rating: float | None = None
    poster_url: str | None = None
    backdrop_url: str | None = None
    similarity: float = 0.0
    matched_by: str | None = None


class MetadataProvider(ABC):
    """Interface commune des fournisseurs de métadonnées."""

    name = "abstract"

    @abstractmethod
    def search(self, title: str, limit: int = 5) -> list[MetadataCandidate]:
        """Recherche un animé par titre ; renvoie des candidats triés."""

    @abstractmethod
    def fetch(self, provider_id: str) -> MetadataAnime | None:
        """Récupère la fiche complète d'un animé (par identifiant fournisseur)."""

    def fetch_episodes(self, provider_id: str) -> tuple[MetadataEpisode, ...]:
        """Titres d'épisodes officiels (si le fournisseur les expose)."""
        return ()
