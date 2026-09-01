"""Regroupement des publications : plusieurs versions d'un même épisode.

    Publication A : Solo Leveling S02E08 1080p      ┐
    Publication B : Solo Leveling S02E08 720p       ├─→ 1 épisode, 3 versions
    Publication C : Solo Leveling S02E08 480p       ┘

Clé logique : anime + saison + épisode + langue (+ sous-titres).
Toutes les qualités sont conservées (aucune suppression) ; la meilleure
version est simplement signalée via le rang de qualité.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .models import STATUS_HIGH, STATUS_MEDIUM, AnalysisResult

_STATUS_ORDER = {"needs_review": 0, "low": 1, "medium": 2, "high": 3}


def group_key(result: AnalysisResult) -> str | None:
    """Clé logique d'un épisode ; None si l'analyse est inexploitable (sans titre)."""
    base = result.anime_key or result.title_key
    if not base:
        return None
    return "|".join(
        (
            base,
            f"S{result.season if result.season is not None else ''}",
            f"E{result.episode if result.episode is not None else ''}",
            result.episode_kind or "regular",
            result.language or "",
            result.subtitles or "",
        )
    )


@dataclass
class EpisodeGroup:
    key: str
    anime_key: str
    title: str
    title_matched: bool
    season: int | None
    episode: int | None
    episode_kind: str | None
    language: str
    subtitles: str | None
    versions: list[AnalysisResult] = field(default_factory=list)
    best_confidence: int = 0
    best_status: str = "needs_review"

    def add(self, result: AnalysisResult) -> str:
        """Ajoute une version ; renvoie « added » ou « duplicate »."""
        if self._is_duplicate(result):
            return "duplicate"
        self.versions.append(result)
        self.versions.sort(key=lambda v: v.quality_rank, reverse=True)
        self.best_confidence = max(self.best_confidence, result.confidence)
        if _STATUS_ORDER.get(result.status, 0) > _STATUS_ORDER.get(self.best_status, 0):
            self.best_status = result.status
        return "added"

    def _is_duplicate(self, result: AnalysisResult) -> bool:
        for existing in self.versions:
            # Même message Telegram analysé deux fois.
            if (
                existing.telegram_message_id is not None
                and result.telegram_message_id == existing.telegram_message_id
                and (existing.telegram_channel_id or "") == (result.telegram_channel_id or "")
            ):
                return True
            # Même qualité + même taille + même nom de fichier.
            if (
                existing.quality == result.quality
                and existing.file_size is not None
                and existing.file_size == result.file_size
                and existing.file_name == result.file_name
            ):
                return True
        return False

    @property
    def best_quality(self) -> str | None:
        return self.versions[0].quality if self.versions else None

    def to_dict(self) -> dict:
        return {
            "key": self.key,
            "anime": {
                "key": self.anime_key,
                "title": self.title,
                "matched": self.title_matched,
            },
            "season": self.season,
            "episode": self.episode,
            "episode_kind": self.episode_kind,
            "language": self.language,
            "subtitles": self.subtitles,
            "best_confidence": self.best_confidence,
            "confidence": self.best_status,
            "best_quality": self.best_quality,
            "version_count": len(self.versions),
            "versions": [version.to_dict() for version in self.versions],
        }


class EpisodeGrouper:
    """Regroupe des analyses en épisodes multi-versions."""

    def __init__(self):
        self._groups: dict[str, EpisodeGroup] = {}
        self.duplicates = 0
        self.ungrouped: list[AnalysisResult] = []

    def add(self, result: AnalysisResult) -> EpisodeGroup | None:
        key = group_key(result)
        if key is None:
            self.ungrouped.append(result)
            return None
        group = self._groups.get(key)
        if group is None:
            group = EpisodeGroup(
                key=key,
                anime_key=result.anime_key or result.title_key or "",
                title=result.title or (result.anime_key or result.title_key or ""),
                title_matched=result.title_matched,
                season=result.season,
                episode=result.episode,
                episode_kind=result.episode_kind,
                language=result.language or "unknown",
                subtitles=result.subtitles,
            )
            self._groups[key] = group
        outcome = group.add(result)
        if outcome == "duplicate":
            self.duplicates += 1
        return group

    def groups(self) -> list[EpisodeGroup]:
        """Groupes triés : meilleur statut d'abord, puis confiance décroissante."""
        return sorted(
            self._groups.values(),
            key=lambda group: (
                _STATUS_ORDER.get(group.best_status, 0),
                group.best_confidence,
                group.title,
            ),
            reverse=True,
        )

    def to_dict(self) -> list[dict]:
        return [group.to_dict() for group in self.groups()]

    def __len__(self) -> int:
        return len(self._groups)
