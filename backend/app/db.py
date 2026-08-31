"""Persistance locale du backend (SQLite) : sources, publications,
statistiques, historique et jetons d'accès.

Aucune donnée sensible Telegram (access_hash, session) n'est stockée ici :
la session Telethon vit dans SESSION_DIR (hors dépôt) et l'access_hash
n'est jamais renvoyé au client.
"""
import sqlite3
import threading
import uuid
from datetime import datetime, timezone

from . import config

_lock = threading.Lock()


def _connect() -> sqlite3.Connection:
    connection = sqlite3.connect(config.DB_PATH, check_same_thread=False)
    connection.row_factory = sqlite3.Row
    return connection


def init_db() -> None:
    with _lock, _connect() as connection:
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS sources (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                username TEXT NOT NULL,
                channel_id INTEGER,
                description TEXT,
                photo_url TEXT,
                kind TEXT NOT NULL DEFAULT 'channel',
                status TEXT NOT NULL DEFAULT 'active',
                sync_enabled INTEGER NOT NULL DEFAULT 1,
                last_sync TEXT,
                analyzed_posts INTEGER NOT NULL DEFAULT 0,
                detected_anime INTEGER NOT NULL DEFAULT 0,
                detected_episodes INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS messages (
                source_id TEXT NOT NULL,
                message_id INTEGER NOT NULL,
                date TEXT NOT NULL,
                text TEXT,
                media_type TEXT NOT NULL,
                file_name TEXT,
                file_size INTEGER,
                link TEXT,
                PRIMARY KEY (source_id, message_id)
            );
            CREATE TABLE IF NOT EXISTS stats (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS sync_history (
                id TEXT PRIMARY KEY,
                date TEXT NOT NULL,
                success INTEGER NOT NULL,
                analyzed_posts INTEGER NOT NULL DEFAULT 0,
                new_episodes INTEGER NOT NULL DEFAULT 0,
                error TEXT
            );
            CREATE TABLE IF NOT EXISTS auth_tokens (
                token TEXT PRIMARY KEY,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS telegram_user (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                data TEXT NOT NULL
            );
            """
        )
        for key, default in (
            ("analyzed_posts", "0"),
            ("detected_anime", "0"),
            ("detected_episodes", "0"),
            ("duplicates_grouped", "0"),
            ("new_episodes", "0"),
            ("last_sync", ""),
        ):
            connection.execute(
                "INSERT OR IGNORE INTO stats(key, value) VALUES (?, ?)", (key, default)
            )


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# Jetons d'accès
# ---------------------------------------------------------------------------


def create_token() -> str:
    token = uuid.uuid4().hex + uuid.uuid4().hex
    with _lock, _connect() as connection:
        connection.execute(
            "INSERT INTO auth_tokens(token, created_at) VALUES (?, ?)",
            (token, _now()),
        )
    return token


def token_exists(token: str) -> bool:
    with _lock, _connect() as connection:
        row = connection.execute(
            "SELECT 1 FROM auth_tokens WHERE token = ?", (token,)
        ).fetchone()
    return row is not None


def revoke_all_tokens() -> None:
    with _lock, _connect() as connection:
        connection.execute("DELETE FROM auth_tokens")


# ---------------------------------------------------------------------------
# Utilisateur Telegram connecté (cache léger : nom, username, téléphone masqué)
# ---------------------------------------------------------------------------


def save_telegram_user(data: dict) -> None:
    import json

    with _lock, _connect() as connection:
        connection.execute(
            "INSERT OR REPLACE INTO telegram_user(id, data) VALUES (1, ?)",
            (json.dumps(data, ensure_ascii=False),),
        )


def get_telegram_user() -> dict | None:
    import json

    with _lock, _connect() as connection:
        row = connection.execute("SELECT data FROM telegram_user WHERE id = 1").fetchone()
    return json.loads(row["data"]) if row else None


def clear_telegram_user() -> None:
    with _lock, _connect() as connection:
        connection.execute("DELETE FROM telegram_user WHERE id = 1")


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------


def list_sources() -> list[dict]:
    with _lock, _connect() as connection:
        rows = connection.execute("SELECT * FROM sources ORDER BY created_at").fetchall()
    return [_source_row(row) for row in rows]


def get_source(source_id: str) -> dict | None:
    with _lock, _connect() as connection:
        row = connection.execute(
            "SELECT * FROM sources WHERE id = ?", (source_id,)
        ).fetchone()
    return _source_row(row) if row else None


def insert_source(source: dict) -> dict:
    with _lock, _connect() as connection:
        connection.execute(
            """INSERT INTO sources(
                   id, name, username, channel_id, description, photo_url, kind,
                   status, sync_enabled, last_sync, analyzed_posts,
                   detected_anime, detected_episodes, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                source["id"],
                source["name"],
                source["username"],
                source.get("channel_id"),
                source.get("description"),
                source.get("photo_url"),
                source.get("kind", "channel"),
                source.get("status", "active"),
                1 if source.get("sync_enabled", True) else 0,
                source.get("last_sync"),
                int(source.get("analyzed_posts", 0)),
                int(source.get("detected_anime", 0)),
                int(source.get("detected_episodes", 0)),
                _now(),
            ),
        )
    return get_source(source["id"])  # type: ignore[return-value]


def update_source(source_id: str, **fields) -> dict | None:
    allowed = {
        "name",
        "status",
        "sync_enabled",
        "last_sync",
        "analyzed_posts",
        "detected_anime",
        "detected_episodes",
        "description",
        "photo_url",
    }
    updates = {key: value for key, value in fields.items() if key in allowed}
    if not updates:
        return get_source(source_id)
    assignments = ", ".join(f"{key} = ?" for key in updates)
    with _lock, _connect() as connection:
        connection.execute(
            f"UPDATE sources SET {assignments} WHERE id = ?",
            (*updates.values(), source_id),
        )
    return get_source(source_id)


def delete_source(source_id: str) -> None:
    with _lock, _connect() as connection:
        connection.execute("DELETE FROM sources WHERE id = ?", (source_id,))
        connection.execute("DELETE FROM messages WHERE source_id = ?", (source_id,))


def _source_row(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "username": row["username"],
        "telegram_link": f"https://t.me/{row['username']}",
        "channel_id": row["channel_id"],
        "description": row["description"],
        "photo_url": row["photo_url"],
        "kind": row["kind"],
        "status": row["status"],
        "sync_enabled": bool(row["sync_enabled"]),
        "last_sync": row["last_sync"],
        "analyzed_posts": row["analyzed_posts"],
        "detected_anime": row["detected_anime"],
        "detected_episodes": row["detected_episodes"],
    }


# ---------------------------------------------------------------------------
# Publications
# ---------------------------------------------------------------------------


def upsert_messages(source_id: str, messages: list[dict]) -> int:
    """Insère les publications ; retourne le nombre de nouvelles entrées."""
    created = 0
    with _lock, _connect() as connection:
        for message in messages:
            cursor = connection.execute(
                "INSERT OR IGNORE INTO messages(source_id, message_id, date, text, "
                "media_type, file_name, file_size, link) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    source_id,
                    int(message["message_id"]),
                    message["date"],
                    message.get("text"),
                    message["media_type"],
                    message.get("file_name"),
                    message.get("file_size"),
                    message.get("link"),
                ),
            )
            created += cursor.rowcount
    return created


def list_messages(source_id: str, limit: int = 20) -> list[dict]:
    with _lock, _connect() as connection:
        rows = connection.execute(
            "SELECT * FROM messages WHERE source_id = ? ORDER BY message_id DESC LIMIT ?",
            (source_id, limit),
        ).fetchall()
    return [
        {
            "message_id": row["message_id"],
            "date": row["date"],
            "text": row["text"],
            "media_type": row["media_type"],
            "file_name": row["file_name"],
            "file_size": row["file_size"],
            "link": row["link"],
        }
        for row in rows
    ]


# ---------------------------------------------------------------------------
# Statistiques & historique
# ---------------------------------------------------------------------------


def get_stats() -> dict:
    with _lock, _connect() as connection:
        rows = connection.execute("SELECT key, value FROM stats").fetchall()
    data = {row["key"]: row["value"] for row in rows}
    return {
        "analyzed_posts": int(data.get("analyzed_posts", "0")),
        "detected_anime": int(data.get("detected_anime", "0")),
        "detected_episodes": int(data.get("detected_episodes", "0")),
        "duplicates_grouped": int(data.get("duplicates_grouped", "0")),
        "new_episodes": int(data.get("new_episodes", "0")),
        "last_sync": data.get("last_sync") or None,
    }


def set_stats(**fields) -> None:
    with _lock, _connect() as connection:
        for key, value in fields.items():
            connection.execute(
                "INSERT INTO stats(key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, str(value)),
            )


def add_history(success: bool, analyzed_posts: int, new_episodes: int, error: str | None = None) -> None:
    with _lock, _connect() as connection:
        connection.execute(
            "INSERT INTO sync_history(id, date, success, analyzed_posts, new_episodes, error) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (uuid.uuid4().hex, _now(), 1 if success else 0, analyzed_posts, new_episodes, error),
        )


def list_history() -> list[dict]:
    with _lock, _connect() as connection:
        rows = connection.execute(
            "SELECT * FROM sync_history ORDER BY date DESC LIMIT 100"
        ).fetchall()
    return [
        {
            "id": row["id"],
            "date": row["date"],
            "success": bool(row["success"]),
            "analyzed_posts": row["analyzed_posts"],
            "new_episodes": row["new_episodes"],
            "error": row["error"],
        }
        for row in rows
    ]
