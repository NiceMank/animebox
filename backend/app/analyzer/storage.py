"""Persistance du moteur : catalogue (anime → saisons → épisodes → versions),
cache d'analyse et travaux par lots.

Les modèles du catalogue ne sont PAS couplés à Telegram : un anime existe
indépendamment de sa source ; seules les versions conservent une référence
au message d'origine. Le cache évite de réanalyser un message inchangé
(identifié par channel + message id + empreinte du contenu).
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
from datetime import datetime, timezone

from .. import config
from .aliases import BUILTIN_ALIASES, BUILTIN_CATALOG
from .text_utils import normalize

_SCHEMA = """
CREATE TABLE IF NOT EXISTS anime (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    original_title TEXT,
    release_year INTEGER,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS anime_alias (
    alias_key TEXT PRIMARY KEY,
    anime_id INTEGER NOT NULL REFERENCES anime(id)
);
CREATE TABLE IF NOT EXISTS season (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    anime_id INTEGER NOT NULL REFERENCES anime(id),
    number INTEGER NOT NULL,
    UNIQUE (anime_id, number)
);
CREATE TABLE IF NOT EXISTS episode (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    season_id INTEGER NOT NULL REFERENCES season(id),
    number INTEGER NOT NULL,
    kind TEXT NOT NULL DEFAULT 'regular',
    title TEXT,
    UNIQUE (season_id, number, kind)
);
CREATE TABLE IF NOT EXISTS episode_version (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    episode_id INTEGER NOT NULL REFERENCES episode(id),
    quality TEXT,
    quality_rank INTEGER NOT NULL DEFAULT 0,
    language TEXT,
    subtitles TEXT,
    media_type TEXT,
    file_name TEXT,
    file_size INTEGER,
    mime_type TEXT,
    duration INTEGER,
    width INTEGER,
    height INTEGER,
    source_id TEXT,
    telegram_message_id INTEGER,
    telegram_message_link TEXT,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS analyzed_messages (
    telegram_channel_id TEXT,
    telegram_message_id INTEGER,
    fingerprint TEXT NOT NULL,
    result_json TEXT NOT NULL,
    status TEXT NOT NULL,
    confidence INTEGER NOT NULL DEFAULT 0,
    analyzed_at TEXT NOT NULL,
    PRIMARY KEY (telegram_channel_id, telegram_message_id)
);
CREATE TABLE IF NOT EXISTS analyzer_jobs (
    id TEXT PRIMARY KEY,
    status TEXT NOT NULL,
    source_id TEXT,
    total INTEGER NOT NULL DEFAULT 0,
    processed INTEGER NOT NULL DEFAULT 0,
    from_cache INTEGER NOT NULL DEFAULT 0,
    new_episodes INTEGER NOT NULL DEFAULT 0,
    new_versions INTEGER NOT NULL DEFAULT 0,
    duplicates INTEGER NOT NULL DEFAULT 0,
    review_needed INTEGER NOT NULL DEFAULT 0,
    error TEXT,
    created_at TEXT NOT NULL,
    finished_at TEXT
);
"""

_lock = threading.Lock()


def _connect() -> sqlite3.Connection:
    connection = sqlite3.connect(config.DB_PATH, check_same_thread=False, timeout=30)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA busy_timeout = 10000")
    return connection


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def init_schema(seed_catalog: bool = True) -> None:
    """Crée les tables du moteur et seed le catalogue intégré (idempotent)."""
    with _lock, _connect() as connection:
        connection.executescript(_SCHEMA)
        if seed_catalog:
            count = connection.execute("SELECT COUNT(*) FROM anime").fetchone()[0]
            if count == 0:
                for title in BUILTIN_CATALOG:
                    cursor = connection.execute(
                        "INSERT INTO anime(key, title, original_title, release_year, created_at) "
                        "VALUES (?, ?, ?, ?, ?)",
                        (title.key, title.title, title.original_title, title.release_year, _now()),
                    )
                    anime_id = cursor.lastrowid
                    for alias in BUILTIN_ALIASES.get(title.key, ()):
                        connection.execute(
                            "INSERT OR IGNORE INTO anime_alias(alias_key, anime_id) VALUES (?, ?)",
                            (normalize(alias), anime_id),
                        )


def message_fingerprint(message: dict) -> str:
    """Empreinte du contenu d'une publication (texte + fichier).

    Deux messages au même id mais au contenu modifié produisent une
    empreinte différente → réanalyse.
    """
    canonical = {
        "text": message.get("text"),
        "file_name": message.get("file_name"),
        "file_size": message.get("file_size"),
        "mime_type": message.get("mime_type"),
        "media_type": message.get("media_type"),
        "duration": message.get("duration"),
        "width": message.get("width"),
        "height": message.get("height"),
    }
    payload = json.dumps(canonical, sort_keys=True, default=str)
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# Cache d'analyse (évite de réanalyser un message inchangé)
# ---------------------------------------------------------------------------


class AnalysisCache:
    def __init__(self):
        init_schema()

    def get(self, channel_id, message_id: int) -> dict | None:
        if message_id is None:
            return None
        with _lock, _connect() as connection:
            row = connection.execute(
                "SELECT fingerprint, result_json, status, confidence FROM analyzed_messages "
                "WHERE telegram_channel_id = ? AND telegram_message_id = ?",
                (str(channel_id) if channel_id is not None else None, int(message_id)),
            ).fetchone()
        return dict(row) if row else None

    def put(self, channel_id, message_id: int, fingerprint: str, result: dict) -> None:
        if message_id is None:
            return
        with _lock, _connect() as connection:
            connection.execute(
                "INSERT OR REPLACE INTO analyzed_messages"
                "(telegram_channel_id, telegram_message_id, fingerprint, result_json,"
                " status, confidence, analyzed_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    str(channel_id) if channel_id is not None else None,
                    int(message_id),
                    fingerprint,
                    json.dumps(result, ensure_ascii=False),
                    result.get("status", "needs_review"),
                    int(result.get("confidence", 0)),
                    _now(),
                ),
            )

    def stats(self) -> dict:
        with _lock, _connect() as connection:
            row = connection.execute(
                "SELECT COUNT(*) AS count, SUM(confidence) AS total_confidence "
                "FROM analyzed_messages"
            ).fetchone()
        return {
            "entries": int(row["count"] or 0),
            "average_confidence": round(row["total_confidence"] / row["count"], 1)
            if row["count"]
            else 0,
        }


# ---------------------------------------------------------------------------
# Catalogue : anime / saison / épisode / version
# ---------------------------------------------------------------------------


class CatalogStore:
    def __init__(self):
        init_schema()

    # -- Anime -------------------------------------------------------------

    def find_anime_by_key_or_alias(self, key: str) -> dict | None:
        with _lock, _connect() as connection:
            row = connection.execute(
                "SELECT * FROM anime WHERE key = ?", (key,)
            ).fetchone()
            if row is None:
                row = connection.execute(
                    "SELECT anime.* FROM anime_alias JOIN anime ON anime.id = anime_alias.anime_id "
                    "WHERE anime_alias.alias_key = ?",
                    (key,),
                ).fetchone()
        return dict(row) if row else None

    def find_or_create_anime(self, key: str, title: str) -> tuple[dict, bool]:
        """Renvoie (anime, créé) — créé=True uniquement lors d'une insertion."""
        existing = self.find_anime_by_key_or_alias(key)
        if existing is not None:
            return existing, False
        with _lock, _connect() as connection:
            connection.execute(
                "INSERT INTO anime(key, title, created_at) VALUES (?, ?, ?)",
                (key, title, _now()),
            )
        created = self.find_anime_by_key_or_alias(key)
        return created, True  # type: ignore[return-value]

    def add_alias(self, anime_key: str, alias: str) -> dict | None:
        anime = self.find_anime_by_key_or_alias(anime_key)
        if anime is None:
            return None
        with _lock, _connect() as connection:
            connection.execute(
                "INSERT OR IGNORE INTO anime_alias(alias_key, anime_id) VALUES (?, ?)",
                (normalize(alias), anime["id"]),
            )
        return anime

    def list_aliases(self) -> list[dict]:
        with _lock, _connect() as connection:
            rows = connection.execute(
                "SELECT anime_alias.alias_key, anime.key AS anime_key "
                "FROM anime_alias JOIN anime ON anime.id = anime_alias.anime_id"
            ).fetchall()
        return [dict(row) for row in rows]

    def list_anime(self) -> list[dict]:
        with _lock, _connect() as connection:
            rows = connection.execute(
                """
                SELECT anime.*,
                       (SELECT COUNT(*) FROM season WHERE season.anime_id = anime.id) AS season_count,
                       (SELECT COUNT(*) FROM episode
                          JOIN season ON season.id = episode.season_id
                         WHERE season.anime_id = anime.id) AS episode_count,
                       (SELECT COUNT(*) FROM episode_version
                          JOIN episode ON episode.id = episode_version.episode_id
                          JOIN season ON season.id = episode.season_id
                         WHERE season.anime_id = anime.id) AS version_count
                FROM anime ORDER BY anime.title
                """
            ).fetchall()
        return [dict(row) for row in rows]

    def anime_detail(self, anime_id: int) -> dict | None:
        with _lock, _connect() as connection:
            anime = connection.execute(
                "SELECT * FROM anime WHERE id = ?", (anime_id,)
            ).fetchone()
            if anime is None:
                return None
            seasons = connection.execute(
                "SELECT * FROM season WHERE anime_id = ? ORDER BY number",
                (anime_id,),
            ).fetchall()
            detail: dict = dict(anime)
            detail["seasons"] = []
            for season in seasons:
                episodes = connection.execute(
                    "SELECT * FROM episode WHERE season_id = ? ORDER BY number",
                    (season["id"],),
                ).fetchall()
                season_data: dict = dict(season)
                season_data["episodes"] = []
                for episode in episodes:
                    versions = connection.execute(
                        "SELECT * FROM episode_version WHERE episode_id = ? "
                        "ORDER BY quality_rank DESC, created_at",
                        (episode["id"],),
                    ).fetchall()
                    episode_data: dict = dict(episode)
                    episode_data["versions"] = [dict(version) for version in versions]
                    season_data["episodes"].append(episode_data)
                detail["seasons"].append(season_data)
        return detail

    # -- Saison / épisode ---------------------------------------------------

    def find_or_create_season(self, anime_id: int, number: int) -> dict:
        with _lock, _connect() as connection:
            row = connection.execute(
                "SELECT * FROM season WHERE anime_id = ? AND number = ?",
                (anime_id, number),
            ).fetchone()
            if row is None:
                connection.execute(
                    "INSERT INTO season(anime_id, number) VALUES (?, ?)",
                    (anime_id, number),
                )
                row = connection.execute(
                    "SELECT * FROM season WHERE anime_id = ? AND number = ?",
                    (anime_id, number),
                ).fetchone()
        return dict(row)

    def find_or_create_episode(
        self, season_id: int, number: int, kind: str, title: str | None
    ) -> tuple[dict, bool]:
        """Renvoie (épisode, créé) — créé=True uniquement lors d'une insertion."""
        with _lock, _connect() as connection:
            row = connection.execute(
                "SELECT * FROM episode WHERE season_id = ? AND number = ? AND kind = ?",
                (season_id, number, kind),
            ).fetchone()
            if row is not None:
                return dict(row), False
            connection.execute(
                "INSERT INTO episode(season_id, number, kind, title) VALUES (?, ?, ?, ?)",
                (season_id, number, kind, title),
            )
            row = connection.execute(
                "SELECT * FROM episode WHERE season_id = ? AND number = ? AND kind = ?",
                (season_id, number, kind),
            ).fetchone()
        return dict(row), True

    # -- Versions -----------------------------------------------------------

    def upsert_version(self, episode_id: int, result) -> str:
        """Ajoute une version d'épisode.

        Renvoie « created » (nouvelle), « updated » (lien actualisé) ou
        « duplicate » (déjà présente : même message ou même fichier).
        Ne supprime jamais une qualité existante.
        """
        message_id = result.telegram_message_id
        with _lock, _connect() as connection:
            if message_id is not None:
                row = connection.execute(
                    "SELECT id FROM episode_version "
                    "WHERE episode_id = ? AND telegram_message_id = ? "
                    "AND source_id IS ?",
                    (episode_id, int(message_id), result.telegram_channel_id),
                ).fetchone()
                if row is not None:
                    connection.execute(
                        "UPDATE episode_version SET telegram_message_link = ?, created_at = ? "
                        "WHERE id = ?",
                        (result.telegram_message_link, _now(), row["id"]),
                    )
                    return "updated"
            # Même fichier (qualité + taille + nom) déjà référencé.
            if result.file_name and result.file_size:
                row = connection.execute(
                    "SELECT id FROM episode_version "
                    "WHERE episode_id = ? AND quality IS ? AND file_size = ? AND file_name = ?",
                    (episode_id, result.quality, int(result.file_size), result.file_name),
                ).fetchone()
                if row is not None:
                    return "duplicate"
            connection.execute(
                """
                INSERT INTO episode_version(
                    episode_id, quality, quality_rank, language, subtitles, media_type,
                    file_name, file_size, mime_type, duration, width, height,
                    source_id, telegram_message_id, telegram_message_link, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    episode_id,
                    result.quality,
                    result.quality_rank,
                    result.language,
                    result.subtitles,
                    result.media_type,
                    result.file_name,
                    result.file_size,
                    result.mime_type,
                    result.duration,
                    result.width,
                    result.height,
                    result.telegram_channel_id,
                    message_id,
                    result.telegram_message_link,
                    _now(),
                ),
            )
        return "created"

    def counts(self) -> dict:
        with _lock, _connect() as connection:
            tables = ("anime", "season", "episode", "episode_version", "anime_alias")
            counts = {}
            for table in tables:
                row = connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()
                counts[table] = int(row[0])
        return counts


# ---------------------------------------------------------------------------
# Travaux d'analyse par lot
# ---------------------------------------------------------------------------


class JobStore:
    def __init__(self):
        init_schema()

    def create(self, job_id: str, source_id: str | None, total: int) -> None:
        with _lock, _connect() as connection:
            connection.execute(
                "INSERT INTO analyzer_jobs(id, status, source_id, total, created_at) "
                "VALUES (?, 'running', ?, ?, ?)",
                (job_id, source_id, total, _now()),
            )

    def update(self, job_id: str, **fields) -> None:
        allowed = {
            "status", "processed", "from_cache", "new_episodes", "new_versions",
            "duplicates", "review_needed", "error", "finished_at",
        }
        updates = {key: value for key, value in fields.items() if key in allowed}
        if not updates:
            return
        assignments = ", ".join(f"{key} = ?" for key in updates)
        with _lock, _connect() as connection:
            connection.execute(
                f"UPDATE analyzer_jobs SET {assignments} WHERE id = ?",
                (*updates.values(), job_id),
            )

    def get(self, job_id: str) -> dict | None:
        with _lock, _connect() as connection:
            row = connection.execute(
                "SELECT * FROM analyzer_jobs WHERE id = ?", (job_id,)
            ).fetchone()
        return dict(row) if row else None

    def running_count(self) -> int:
        with _lock, _connect() as connection:
            row = connection.execute(
                "SELECT COUNT(*) FROM analyzer_jobs WHERE status = 'running'"
            ).fetchone()
        return int(row[0])
