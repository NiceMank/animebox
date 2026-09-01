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


# ---------------------------------------------------------------------------
# Migrations (ajouts de colonnes — SQLite ne connaît pas ALTER COLUMN)
# ---------------------------------------------------------------------------

_METADATA_COLUMNS = (
    "display_title TEXT",
    "alternative_titles TEXT",
    "synopsis TEXT",
    "genres TEXT",
    "year INTEGER",
    "status TEXT",
    "season_count INTEGER",
    "episode_count INTEGER",
    "rating REAL",
    "duration_min INTEGER",
    "poster_url TEXT",
    "backdrop_url TEXT",
    "poster_asset TEXT",
    "backdrop_asset TEXT",
    "metadata_source TEXT",
    "metadata_status TEXT NOT NULL DEFAULT 'pending'",
    "metadata_provider_id TEXT",
    "metadata_confidence REAL",
    "metadata_updated_at TEXT",
    "metadata_candidates TEXT",
    "manually_edited INTEGER NOT NULL DEFAULT 0",
)

_EXTRA_COLUMNS = {
    "season": ("title TEXT", "year INTEGER", "episode_count INTEGER"),
    "episode": ("synopsis TEXT", "air_date TEXT", "thumbnail TEXT"),
}


def _table_columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {
        row[1] for row in connection.execute(f"PRAGMA table_info({table})").fetchall()
    }


def migrate_schema() -> None:
    """Ajoute les colonnes/tables/indexes de l'étape 6 (idempotent)."""
    with _lock, _connect() as connection:
        anime_columns = _table_columns(connection, "anime")
        for definition in _METADATA_COLUMNS:
            name = definition.split()[0]
            if name not in anime_columns:
                connection.execute(f"ALTER TABLE anime ADD COLUMN {definition}")
        for table, definitions in _EXTRA_COLUMNS.items():
            existing = _table_columns(connection, table)
            for definition in definitions:
                name = definition.split()[0]
                if name not in existing:
                    connection.execute(f"ALTER TABLE {table} ADD COLUMN {definition}")
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS catalog_duplicates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                anime_a_id INTEGER NOT NULL,
                anime_b_id INTEGER NOT NULL,
                reason TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'review_required',
                created_at TEXT NOT NULL,
                UNIQUE (anime_a_id, anime_b_id)
            );
            CREATE INDEX IF NOT EXISTS idx_anime_title ON anime(title);
            CREATE INDEX IF NOT EXISTS idx_anime_key ON anime(key);
            CREATE INDEX IF NOT EXISTS idx_anime_metadata_status ON anime(metadata_status);
            CREATE INDEX IF NOT EXISTS idx_alias_key ON anime_alias(alias_key);
            CREATE INDEX IF NOT EXISTS idx_episode_version_episode ON episode_version(episode_id);
            CREATE INDEX IF NOT EXISTS idx_episode_season ON episode(season_id);
            """
        )
        # La table `messages` appartient au module db (backend) : l'index
        # n'est créé que si la table existe.
        tables = {
            row[0] for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            ).fetchall()
        }
        if "messages" in tables:
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_messages_source ON messages(source_id)"
            )


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
    migrate_schema()


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
        """Renvoie (anime, créé) — créé=True uniquement lors d'une insertion.

        Détection de doublons : une nouvelle fiche dont le titre est presque
        identique à une fiche existante est signalée (catalog_duplicates,
        statut review_required) mais JAMAIS fusionnée automatiquement.
        """
        existing = self.find_anime_by_key_or_alias(key)
        if existing is not None:
            return existing, False
        with _lock, _connect() as connection:
            connection.execute(
                "INSERT INTO anime(key, title, created_at) VALUES (?, ?, ?)",
                (key, title, _now()),
            )
        created = self.find_anime_by_key_or_alias(key)
        assert created is not None
        self._flag_near_duplicates(created)
        return created, True

    def _flag_near_duplicates(self, created: dict) -> None:
        """Compare la nouvelle fiche aux existantes (similarité de titre)."""
        import difflib

        created_norm = normalize(created["title"])
        for anime in self.list_anime():
            if anime["id"] == created["id"]:
                continue
            ratio = difflib.SequenceMatcher(
                None, created_norm, normalize(anime["canonical_title"])
            ).ratio()
            if ratio >= 0.92:
                self.add_duplicate(
                    created["id"], anime["id"], "similar_title", round(ratio, 3)
                )

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

    def list_anime(self, offset: int = 0, limit: int | None = None) -> list[dict]:
        with _lock, _connect() as connection:
            query = (
                """
                SELECT anime.*,
                       (SELECT COUNT(*) FROM season WHERE season.anime_id = anime.id) AS stored_season_count,
                       (SELECT COUNT(*) FROM episode
                          JOIN season ON season.id = episode.season_id
                         WHERE season.anime_id = anime.id) AS stored_episode_count,
                       (SELECT COUNT(*) FROM episode_version
                          JOIN episode ON episode.id = episode_version.episode_id
                          JOIN season ON season.id = episode.season_id
                         WHERE season.anime_id = anime.id) AS version_count
                FROM anime ORDER BY anime.title
                """
            )
            if limit is not None:
                query += " LIMIT ? OFFSET ?"
                rows = connection.execute(query, (limit, offset)).fetchall()
            else:
                rows = connection.execute(query).fetchall()
        return [self._anime_public(row) for row in rows]

    def count_anime(self) -> int:
        with _lock, _connect() as connection:
            return int(connection.execute("SELECT COUNT(*) FROM anime").fetchone()[0])

    # -- Sérialisation publique (aucune donnée sensible) --------------------

    @staticmethod
    def _decode_list(value) -> list:
        if not value:
            return []
        try:
            decoded = json.loads(value)
            return decoded if isinstance(decoded, list) else []
        except (TypeError, ValueError):
            return []

    def _anime_public(self, row: sqlite3.Row) -> dict:
        data = dict(row)
        stored_season_count = data.pop("stored_season_count", None)
        stored_episode_count = data.pop("stored_episode_count", None)
        version_count = data.pop("version_count", None)
        return {
            "id": data["id"],
            "key": data["key"],
            "canonical_title": data["title"],
            "display_title": data.get("display_title") or data["title"],
            "original_title": data.get("original_title"),
            "alternative_titles": self._decode_list(data.get("alternative_titles")),
            "synopsis": data.get("synopsis"),
            "genres": self._decode_list(data.get("genres")),
            "year": data.get("year"),
            "status": data.get("status"),
            "season_count": data.get("season_count"),
            "episode_count": data.get("episode_count"),
            "stored_season_count": stored_season_count,
            "stored_episode_count": stored_episode_count,
            "version_count": version_count,
            "rating": data.get("rating"),
            "duration_min": data.get("duration_min"),
            "poster_url": data.get("poster_url"),
            "backdrop_url": data.get("backdrop_url"),
            "poster_asset": data.get("poster_asset"),
            "backdrop_asset": data.get("backdrop_asset"),
            "metadata_source": data.get("metadata_source"),
            "metadata_status": data.get("metadata_status") or "pending",
            "metadata_confidence": data.get("metadata_confidence"),
            "metadata_updated_at": data.get("metadata_updated_at"),
            "metadata_candidates": self._decode_list(data.get("metadata_candidates")),
            "manually_edited": bool(data.get("manually_edited")),
            "release_year": data.get("release_year"),
            "created_at": data.get("created_at"),
        }

    def _version_public(self, version: sqlite3.Row, channel_username: str | None) -> dict:
        data = dict(version)
        width, height = data.get("width"), data.get("height")
        resolution = f"{width}x{height}" if width and height else None
        return {
            "id": data["id"],
            "quality": data["quality"],
            "quality_rank": data["quality_rank"],
            "resolution": resolution,
            "language": data["language"],
            "subtitles": data["subtitles"],
            "media_type": data["media_type"],
            "file_name": data["file_name"],
            "file_size": data["file_size"],
            "mime_type": data["mime_type"],
            "duration": data["duration"],
            "width": width,
            "height": height,
            "created_at": data["created_at"],
            # Références Telegram conservées (rétro-compatibilité + objet source).
            "source_id": data["source_id"],
            "telegram_message_id": data["telegram_message_id"],
            "telegram_message_link": data["telegram_message_link"],
            "source": {
                "channel_id": data["source_id"],
                "channel_username": channel_username,
                "telegram_message_id": data["telegram_message_id"],
                "telegram_message_link": data["telegram_message_link"],
            },
        }

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
            detail: dict = self._anime_public(anime)
            detail["seasons"] = []
            for season in seasons:
                episodes = connection.execute(
                    "SELECT * FROM episode WHERE season_id = ? ORDER BY number",
                    (season["id"],),
                ).fetchall()
                season_data: dict = {
                    "id": season["id"],
                    "number": season["number"],
                    "title": season["title"],
                    "year": season["year"],
                    "episode_count": season["episode_count"],
                }
                season_data["episodes"] = []
                for episode in episodes:
                    versions = connection.execute(
                        "SELECT * FROM episode_version WHERE episode_id = ? "
                        "ORDER BY quality_rank DESC, created_at",
                        (episode["id"],),
                    ).fetchall()
                    episode_data: dict = {
                        "id": episode["id"],
                        "number": episode["number"],
                        "kind": episode["kind"],
                        "title": episode["title"],
                        "synopsis": episode["synopsis"],
                        "air_date": episode["air_date"],
                        "thumbnail": episode["thumbnail"],
                    }
                    sources_table = any(
                        row[0] == "sources"
                        for row in connection.execute(
                            "SELECT name FROM sqlite_master WHERE type='table' AND name='sources'"
                        ).fetchall()
                    )
                    episode_data["versions"] = [
                        self._version_public(
                            version,
                            self._channel_username(connection, version["source_id"])
                            if sources_table
                            else None,
                        )
                        for version in versions
                    ]
                    episode_data["version_count"] = len(episode_data["versions"])
                    episode_data["best_version"] = self.best_version(episode_data["versions"])
                    season_data["episodes"].append(episode_data)
                detail["seasons"].append(season_data)
        return detail

    # -- Métadonnées enrichies ----------------------------------------------

    def update_anime_metadata(self, anime_id: int, fields: dict) -> dict | None:
        """Met à jour les champs d'enrichissement (encodage JSON des listes)."""
        allowed = {
            "display_title", "original_title", "alternative_titles", "synopsis",
            "genres", "year", "status", "season_count", "episode_count", "rating",
            "duration_min", "poster_url", "backdrop_url", "poster_asset",
            "backdrop_asset", "metadata_source", "metadata_status",
            "metadata_provider_id", "metadata_confidence", "metadata_updated_at",
            "metadata_candidates", "manually_edited",
        }
        updates = {key: value for key, value in fields.items() if key in allowed}
        if not updates:
            return self.get_anime_public(anime_id)
        for key in ("alternative_titles", "genres", "metadata_candidates"):
            if key in updates and updates[key] is not None and not isinstance(updates[key], str):
                updates[key] = json.dumps(updates[key], ensure_ascii=False)
        if "manually_edited" in updates and isinstance(updates["manually_edited"], bool):
            updates["manually_edited"] = int(updates["manually_edited"])
        assignments = ", ".join(f"{key} = ?" for key in updates)
        with _lock, _connect() as connection:
            connection.execute(
                f"UPDATE anime SET {assignments} WHERE id = ?",
                (*updates.values(), anime_id),
            )
            row = connection.execute("SELECT * FROM anime WHERE id = ?", (anime_id,)).fetchone()
        return self._anime_public(row) if row else None

    def get_anime_public(self, anime_id: int) -> dict | None:
        with _lock, _connect() as connection:
            row = connection.execute("SELECT * FROM anime WHERE id = ?", (anime_id,)).fetchone()
        return self._anime_public(row) if row else None

    def reassign_version(
        self,
        version_id: int,
        *,
        season_number: int | None = None,
        episode_number: int | None = None,
        anime_id: int | None = None,
    ) -> dict | None:
        """Correction manuelle (admin) : déplace une publication vers une
        autre saison/épisode (et éventuellement un autre animé).

        Le regroupement n'est jamais modifié automatiquement : seul un
        administrateur appelle cette méthode (jamais de suppression).
        """
        with _lock, _connect() as connection:
            row = connection.execute(
                "SELECT * FROM episode_version WHERE id = ?", (version_id,)
            ).fetchone()
            if row is None:
                return None
            current_episode_id = row["episode_id"]
            current_episode = connection.execute(
                "SELECT number, season_id FROM episode WHERE id = ?", (current_episode_id,)
            ).fetchone()
            if current_episode is None:
                return None
            target_season_id = current_episode["season_id"]
            if anime_id is not None:
                target_anime_id = anime_id
            else:
                target_anime_id = connection.execute(
                    "SELECT anime_id FROM season WHERE id = ?", (target_season_id,)
                ).fetchone()["anime_id"]
            if season_number is not None:
                season_row = connection.execute(
                    "SELECT id FROM season WHERE anime_id = ? AND number = ?",
                    (target_anime_id, season_number),
                ).fetchone()
                if season_row is None:
                    cursor = connection.execute(
                        "INSERT INTO season (anime_id, number) VALUES (?, ?)",
                        (target_anime_id, season_number),
                    )
                    target_season_id = cursor.lastrowid
                else:
                    target_season_id = season_row["id"]
            wanted_number = episode_number if episode_number is not None else current_episode["number"]
            episode_row = connection.execute(
                "SELECT id FROM episode WHERE season_id = ? AND number = ?",
                (target_season_id, wanted_number),
            ).fetchone()
            if episode_row is None:
                cursor = connection.execute(
                    "INSERT INTO episode (season_id, number, kind) VALUES (?, ?, 'regular')",
                    (target_season_id, wanted_number),
                )
                target_episode_id = cursor.lastrowid
            else:
                target_episode_id = episode_row["id"]
            connection.execute(
                "UPDATE episode_version SET episode_id = ? WHERE id = ?",
                (target_episode_id, version_id),
            )
        anime_row = self._anime_row_by_episode(target_episode_id)
        if anime_row is None:
            return self.get_anime_public(target_anime_id)
        return self.get_anime_public(anime_row["id"])

    def _anime_row_by_episode(self, episode_id: int):
        with _lock, _connect() as connection:
            row = connection.execute(
                "SELECT a.* FROM anime a JOIN season s ON s.anime_id = a.id "
                "JOIN episode e ON e.season_id = s.id WHERE e.id = ?",
                (episode_id,),
            ).fetchone()
        return row

    # -- Recherche ----------------------------------------------------------

    def search_anime(self, query: str, limit: int = 25, offset: int = 0) -> list[dict]:
        """Recherche titre canonique / original / alternatifs / alias.

        La requête est normalisée (casse, accents, séparateurs) avant
        comparaison, comme dans le moteur d'analyse.
        """
        term = normalize(query)
        if not term:
            return []
        pattern = f"%{term}%"
        with _lock, _connect() as connection:
            rows = connection.execute(
                """
                SELECT DISTINCT anime.*, al.alias_key AS matched_alias
                FROM anime
                LEFT JOIN anime_alias al ON al.anime_id = anime.id
                WHERE anime.title LIKE ? COLLATE NOCASE
                   OR anime.original_title LIKE ? COLLATE NOCASE
                   OR anime.alternative_titles LIKE ? COLLATE NOCASE
                   OR anime.key LIKE ? COLLATE NOCASE
                   OR al.alias_key LIKE ?
                ORDER BY anime.title
                LIMIT ? OFFSET ?
                """,
                (pattern, pattern, pattern, pattern, pattern, limit, offset),
            ).fetchall()
        results = []
        for row in rows:
            anime = self._anime_public(row)
            matched_alias = row["matched_alias"]
            # Champ de correspondance précis (pour l'interface).
            normalized_titles = [normalize(t) for t in (
                anime["canonical_title"], anime["original_title"],
                *anime["alternative_titles"],
            ) if t]
            if term == normalize(anime["canonical_title"]):
                matched_via, matched_text = "title", anime["canonical_title"]
            elif matched_alias and term == matched_alias:
                matched_via, matched_text = "alias", matched_alias
            elif term in normalized_titles:
                matched_via, matched_text = "alternative", next(
                    t for t in anime["alternative_titles"] + [anime["original_title"]]
                    if t and normalize(t) == term
                )
            else:
                matched_via, matched_text = "partial", None
            results.append({
                **anime,
                "match": {
                    "matched_via": matched_via,
                    "matched_text": matched_text,
                    "matched_alias": matched_alias,
                },
            })
        return results

    # -- Épisodes récents ----------------------------------------------------

    def recent_episodes(self, limit: int = 20) -> list[dict]:
        """Derniers épisodes alimentés, avec meilleure version par épisode."""
        with _lock, _connect() as connection:
            rows = connection.execute(
                """
                SELECT e.id AS episode_id, e.number, e.kind, e.title AS episode_title,
                       e.season_id, s.number AS season_number, s.anime_id,
                       a.key AS anime_key, a.title AS anime_title,
                       a.poster_url, a.poster_asset, a.backdrop_asset,
                       a.metadata_status,
                       (SELECT MAX(ev2.created_at) FROM episode_version ev2
                         WHERE ev2.episode_id = e.id) AS newest_created_at,
                       (SELECT COUNT(*) FROM episode_version ev2
                         WHERE ev2.episode_id = e.id) AS version_count
                FROM episode e
                JOIN season s ON s.id = e.season_id
                JOIN anime a ON a.id = s.anime_id
                WHERE (SELECT COUNT(*) FROM episode_version ev2
                        WHERE ev2.episode_id = e.id) > 0
                ORDER BY newest_created_at DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        recent = []
        for row in rows:
            versions = self._episode_versions(row["episode_id"])
            data = dict(row)
            data["versions"] = versions
            data["best"] = self.best_version(versions)
            recent.append(data)
        return recent

    def _episode_versions(self, episode_id: int) -> list[dict]:
        with _lock, _connect() as connection:
            rows = connection.execute(
                "SELECT * FROM episode_version WHERE episode_id = ? "
                "ORDER BY quality_rank DESC, created_at",
                (episode_id,),
            ).fetchall()
            sources_table = any(
                row[0] == "sources"
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name='sources'"
                ).fetchall()
            )
            public = []
            for row in rows:
                username = (
                    self._channel_username(connection, row["source_id"])
                    if sources_table
                    else None
                )
                public.append(self._version_public(row, username))
        return public

    @staticmethod
    def _channel_username(connection: sqlite3.Connection, channel_id) -> str | None:
        if channel_id is None:
            return None
        row = connection.execute(
            "SELECT username FROM sources WHERE channel_id = ?", (channel_id,)
        ).fetchone()
        return row["username"] if row else None

    @staticmethod
    def best_version(versions: list[dict]) -> dict | None:
        """Meilleure version d'un épisode (qualité, langue, fraîcheur…).

        Importé dynamiquement pour éviter un cycle d'imports.
        """
        from ..catalog import priorities  # noqa: PLC0415

        return priorities.best_version(versions)

    # -- Doublons ------------------------------------------------------------

    def add_duplicate(self, anime_a_id: int, anime_b_id: int, reason: str, confidence: float) -> dict | None:
        low, high = sorted((int(anime_a_id), int(anime_b_id)))
        with _lock, _connect() as connection:
            connection.execute(
                "INSERT OR IGNORE INTO catalog_duplicates"
                "(anime_a_id, anime_b_id, reason, confidence, created_at) "
                "VALUES (?, ?, ?, ?, ?)",
                (low, high, reason, confidence, _now()),
            )
            row = connection.execute(
                "SELECT * FROM catalog_duplicates WHERE anime_a_id = ? AND anime_b_id = ?",
                (low, high),
            ).fetchone()
        return dict(row) if row else None

    def list_duplicates(self, status: str | None = "review_required") -> list[dict]:
        query = """
            SELECT d.*, a.title AS title_a, b.title AS title_b
            FROM catalog_duplicates d
            JOIN anime a ON a.id = d.anime_a_id
            JOIN anime b ON b.id = d.anime_b_id
        """
        params: tuple = ()
        if status is not None:
            query += " WHERE d.status = ?"
            params = (status,)
        query += " ORDER BY d.created_at DESC"
        with _lock, _connect() as connection:
            rows = connection.execute(query, params).fetchall()
        return [dict(row) for row in rows]

    def resolve_duplicate(self, duplicate_id: int, resolution: str) -> dict | None:
        with _lock, _connect() as connection:
            connection.execute(
                "UPDATE catalog_duplicates SET status = ? WHERE id = ?",
                (resolution, duplicate_id),
            )
            row = connection.execute(
                "SELECT * FROM catalog_duplicates WHERE id = ?", (duplicate_id,)
            ).fetchone()
        return dict(row) if row else None

    def merge_anime(self, target_id: int, source_id: int) -> dict | None:
        """Fusion manuelle (administration) : déplace le contenu de la source
        vers la cible, ajoute un alias, puis supprime la fiche source.

        Jamais appelé automatiquement : la fusion est toujours explicite.
        """
        source = self.get_anime_public(source_id)
        target = self.get_anime_public(target_id)
        if source is None or target is None or target_id == source_id:
            return None
        with _lock, _connect() as connection:
            # Alias : l'ancien titre canonique de la source devient un alias.
            connection.execute(
                "INSERT OR IGNORE INTO anime_alias(alias_key, anime_id) VALUES (?, ?)",
                (source["key"], target_id),
            )
            source_seasons = connection.execute(
                "SELECT * FROM season WHERE anime_id = ?", (source_id,)
            ).fetchall()
            for season in source_seasons:
                target_season = connection.execute(
                    "SELECT * FROM season WHERE anime_id = ? AND number = ?",
                    (target_id, season["number"]),
                ).fetchone()
                if target_season is None:
                    connection.execute(
                        "UPDATE season SET anime_id = ? WHERE id = ?",
                        (target_id, season["id"]),
                    )
                else:
                    connection.execute(
                        "UPDATE episode SET season_id = ? WHERE season_id = ?",
                        (target_season["id"], season["id"]),
                    )
                    connection.execute("DELETE FROM season WHERE id = ?", (season["id"],))
            connection.execute("DELETE FROM anime WHERE id = ?", (source_id,))
            # Les signalements impliquant les deux fiches sont résolus ; les
            # autres signalements référençant la source pointent vers la cible.
            connection.execute(
                "UPDATE catalog_duplicates SET status = 'resolved_merged' "
                "WHERE (anime_a_id = ? AND anime_b_id = ?) OR (anime_a_id = ? AND anime_b_id = ?)",
                (source_id, target_id, target_id, source_id),
            )
            connection.execute(
                "UPDATE catalog_duplicates SET anime_a_id = ? WHERE anime_a_id = ?",
                (target_id, source_id),
            )
            connection.execute(
                "UPDATE catalog_duplicates SET anime_b_id = ? WHERE anime_b_id = ?",
                (target_id, source_id),
            )
            connection.execute(
                "DELETE FROM catalog_duplicates WHERE anime_a_id = anime_b_id "
                "AND status != 'resolved_merged'"
            )
        return self.anime_detail(target_id)

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
