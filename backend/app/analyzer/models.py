"""Modèles de données du moteur d'analyse (sans dépendance Telegram).

Un Anime peut exister indépendamment de toute source : les modèles de
catalogue (anime / saison / épisode / version) ne connaissent pas Telegram.
Seuls les champs ``telegram_*`` d'une version conservent la référence au
message d'origine.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

STATUS_HIGH = "high"
STATUS_MEDIUM = "medium"
STATUS_LOW = "low"
STATUS_NEEDS_REVIEW = "needs_review"

STATUSES = (STATUS_HIGH, STATUS_MEDIUM, STATUS_LOW, STATUS_NEEDS_REVIEW)

MEDIA_TYPES = ("video", "document", "image", "audio", "text", "unknown")

# Statuts suffisamment fiables pour alimenter le catalogue automatiquement.
INGESTIBLE_STATUSES = {STATUS_HIGH, STATUS_MEDIUM}


@dataclass
class AnalysisResult:
    """Résultat complet de l'analyse d'une publication."""

    status: str = STATUS_NEEDS_REVIEW
    confidence: int = 0
    title: str | None = None
    title_key: str | None = None
    title_matched: bool = False
    title_via_alias: bool = False
    anime_key: str | None = None  # clé canonique du catalogue
    original_title: str | None = None
    release_year: int | None = None
    season: int | None = None
    season_source: str | None = None
    episode: int | None = None
    episode_kind: str | None = None
    episode_source: str | None = None
    year: int | None = None
    quality: str | None = None
    quality_original: str | None = None
    quality_source: str | None = None
    quality_rank: int = 0
    language: str = "unknown"
    subtitles: str | None = None
    media_type: str = "unknown"
    file_name: str | None = None
    file_size: int | None = None
    mime_type: str | None = None
    duration: int | None = None
    width: int | None = None
    height: int | None = None
    telegram_channel_id: str | None = None
    telegram_channel_username: str | None = None
    telegram_message_id: int | None = None
    telegram_message_link: str | None = None
    warnings: list[str] = field(default_factory=list)

    # -- Sérialisation -------------------------------------------------------

    def to_dict(self) -> dict:
        data = asdict(self)
        data.pop("file_name", None)
        data.pop("file_size", None)
        data.pop("mime_type", None)
        data.pop("duration", None)
        data.pop("width", None)
        data.pop("height", None)
        data["file"] = {
            "file_name": self.file_name,
            "file_size": self.file_size,
            "mime_type": self.mime_type,
            "duration": self.duration,
            "width": self.width,
            "height": self.height,
        }
        telegram = {
            "channel_id": self.telegram_channel_id,
            "channel_username": self.telegram_channel_username,
            "message_id": self.telegram_message_id,
            "message_link": self.telegram_message_link,
        }
        if any(value is not None for value in telegram.values()):
            data["telegram"] = telegram
        else:
            data["telegram"] = None
        return data

    @classmethod
    def from_dict(cls, data: dict) -> "AnalysisResult":
        file_info = data.get("file") or {}
        telegram = data.get("telegram") or {}
        return cls(
            status=data.get("status", STATUS_NEEDS_REVIEW),
            confidence=int(data.get("confidence", 0)),
            title=data.get("title"),
            title_key=data.get("title_key"),
            title_matched=bool(data.get("title_matched")),
            title_via_alias=bool(data.get("title_via_alias")),
            anime_key=data.get("anime_key"),
            original_title=data.get("original_title"),
            release_year=data.get("release_year"),
            season=data.get("season"),
            season_source=data.get("season_source"),
            episode=data.get("episode"),
            episode_kind=data.get("episode_kind"),
            episode_source=data.get("episode_source"),
            year=data.get("year"),
            quality=data.get("quality"),
            quality_original=data.get("quality_original"),
            quality_source=data.get("quality_source"),
            quality_rank=int(data.get("quality_rank") or 0),
            language=data.get("language") or "unknown",
            subtitles=data.get("subtitles"),
            media_type=data.get("media_type") or "unknown",
            file_name=file_info.get("file_name"),
            file_size=file_info.get("file_size"),
            mime_type=file_info.get("mime_type"),
            duration=file_info.get("duration"),
            width=file_info.get("width"),
            height=file_info.get("height"),
            telegram_channel_id=telegram.get("channel_id"),
            telegram_channel_username=telegram.get("channel_username"),
            telegram_message_id=telegram.get("message_id"),
            telegram_message_link=telegram.get("message_link"),
            warnings=list(data.get("warnings") or []),
        )

    def display(self) -> str:
        """Ligne de log lisible (jamais de secret)."""
        season = f"S{self.season:02d}" if self.season else "S?"
        episode = f"E{self.episode:02d}" if self.episode else "E?"
        return (
            f"{self.title or '?'} {season}{episode} "
            f"{self.quality or '?'} {self.language or '?'} "
            f"{self.confidence}% [{self.status}]"
        )
