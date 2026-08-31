"""API HTTP du backend AnimeBox.

Application mobile  ──HTTPS──►  Backend API (ce fichier)
                                      │
                              Service Telegram (telegram_client.py)
                                      │
                                  Telegram API

Aucun secret Telegram ne transite vers le client : API_ID/API_HASH ne
vivent que dans les variables d'environnement du serveur, la session
Telethon vit dans SESSION_DIR (hors dépôt) et l'access_hash des canaux
n'est jamais renvoyé.
"""
import re

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import config, db
from .errors import ApiError, bad_input, not_connected, unauthorized
from .telegram_client import build_gateway, normalize_input

app = FastAPI(title="AnimeBox Backend", version="0.4.0")

# CORS ouvert pour le développement (le client mobile/web n'est pas servi
# par ce serveur). À restreindre en production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

gateway = build_gateway()
db.init_db()

# Photos de profil téléchargées (mode réel uniquement).
try:
    app.mount("/api/assets", StaticFiles(directory=config.UPLOADS_DIR), name="assets")
except RuntimeError:
    pass


# ---------------------------------------------------------------------------
# Modèles de requêtes
# ---------------------------------------------------------------------------

_PHONE_RE = re.compile(r"^\+?[0-9 ()-]{6,15}$")
_CODE_RE = re.compile(r"^[0-9]{4,6}$")


class SendCodeBody(BaseModel):
    phone: str = Field(min_length=6, max_length=20)


class VerifyCodeBody(BaseModel):
    phone: str = Field(min_length=6, max_length=20)
    code: str = Field(min_length=4, max_length=6)


class ResolveBody(BaseModel):
    input: str = Field(min_length=3, max_length=64)


class AddSourceBody(BaseModel):
    input: str = Field(min_length=3, max_length=64)
    name: str | None = None


class UpdateSourceBody(BaseModel):
    sync_enabled: bool | None = None


# ---------------------------------------------------------------------------
# Authentification par jeton
# ---------------------------------------------------------------------------


def require_auth(authorization: str | None = Header(default=None)) -> None:
    if not authorization or not authorization.startswith("Bearer "):
        raise unauthorized()
    token = authorization.removeprefix("Bearer ").strip()
    if not db.token_exists(token):
        raise unauthorized()


@app.exception_handler(ApiError)
async def handle_api_error(request: Request, error: ApiError):
    from fastapi.responses import JSONResponse

    return JSONResponse(
        status_code=error.status,
        content={"error": {"code": error.code, "message": error.message}},
    )


@app.exception_handler(HTTPException)
async def handle_http_exception(request: Request, error: HTTPException):
    from fastapi.responses import JSONResponse

    return JSONResponse(
        status_code=error.status_code,
        content={"error": {"code": "HTTP_ERROR", "message": str(error.detail)}},
    )


# ---------------------------------------------------------------------------
# Santé
# ---------------------------------------------------------------------------


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "mode": "mock" if config.MOCK_MODE else "telegram",
        "telegram_connected": gateway.is_connected(),
    }


# ---------------------------------------------------------------------------
# Authentification Telegram
# ---------------------------------------------------------------------------


@app.post("/api/telegram/send-code")
def send_code(body: SendCodeBody) -> dict:
    phone = body.phone.strip()
    if not _PHONE_RE.match(phone):
        raise bad_input("Numéro de téléphone invalide.")
    try:
        gateway.send_code(phone)
    except ApiError:
        raise
    except Exception:  # noqa: BLE001
        from .errors import telegram_error

        raise telegram_error("Impossible d'envoyer le code de connexion.")
    return {"sent": True}


@app.post("/api/telegram/verify-code")
def verify_code(body: VerifyCodeBody) -> dict:
    if not _CODE_RE.match(body.code.strip()):
        raise bad_input("Code de connexion invalide.")
    user = gateway.verify_code(body.phone.strip(), body.code.strip())
    db.save_telegram_user(user)
    return {"token": db.create_token(), "user": user}


@app.get("/api/telegram/status", dependencies=[Depends(require_auth)])
def telegram_status() -> dict:
    user = db.get_telegram_user()
    if user is None:
        user = gateway.current_user()
        if user is not None:
            db.save_telegram_user(user)
    return {"connected": user is not None, "user": user}


@app.post("/api/telegram/logout", dependencies=[Depends(require_auth)])
def telegram_logout() -> dict:
    try:
        gateway.logout()
    except ApiError:
        pass
    db.revoke_all_tokens()
    db.clear_telegram_user()
    return {"ok": True}


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------


def _source_public(source: dict) -> dict:
    """Renvoie la source sans aucune donnée sensible (pas d'access_hash)."""
    return source


@app.get("/api/sources", dependencies=[Depends(require_auth)])
def list_sources() -> dict:
    return {"sources": [_source_public(source) for source in db.list_sources()]}


@app.post("/api/sources/resolve", dependencies=[Depends(require_auth)])
def resolve_source(body: ResolveBody) -> dict:
    username = normalize_input(body.input)
    resolved = gateway.resolve(username)
    return {"channel": resolved}


@app.post("/api/sources", dependencies=[Depends(require_auth)])
def add_source(body: AddSourceBody) -> dict:
    username = normalize_input(body.input)
    resolved = gateway.resolve(username)
    import uuid

    source = {
        "id": uuid.uuid4().hex,
        "name": (body.name or resolved["title"]),
        "username": resolved["username"],
        "channel_id": resolved.get("channel_id"),
        "description": resolved.get("description"),
        "photo_url": resolved.get("photo_url"),
        "kind": resolved.get("kind", "channel"),
        "status": "active",
        "sync_enabled": True,
        "last_sync": None,
    }
    return {"source": _source_public(db.insert_source(source))}


@app.patch("/api/sources/{source_id}", dependencies=[Depends(require_auth)])
def update_source(source_id: str, body: UpdateSourceBody) -> dict:
    source = db.get_source(source_id)
    if source is None:
        raise ApiError("SOURCE_NOT_FOUND", "Source introuvable.", 404)
    fields = {}
    if body.sync_enabled is not None:
        fields["sync_enabled"] = body.sync_enabled
        fields["status"] = "active" if body.sync_enabled else "disabled"
    updated = db.update_source(source_id, **fields)
    return {"source": _source_public(updated)}


@app.delete("/api/sources/{source_id}", dependencies=[Depends(require_auth)])
def delete_source(source_id: str) -> dict:
    if db.get_source(source_id) is None:
        raise ApiError("SOURCE_NOT_FOUND", "Source introuvable.", 404)
    db.delete_source(source_id)
    return {"ok": True}


# ---------------------------------------------------------------------------
# Publications récentes (récupération de test — l'analyse viendra ensuite)
# ---------------------------------------------------------------------------


def _fetch_and_store(source: dict, limit: int) -> tuple[int, int]:
    """Récupère les publications et les stocke.

    Retourne (nombre de publications récupérées, nombre de nouvelles).
    """
    messages = gateway.fetch_messages(source["username"], source.get("channel_id"), limit)
    created = db.upsert_messages(source["id"], messages)
    return len(messages), created


@app.get("/api/sources/{source_id}/messages", dependencies=[Depends(require_auth)])
def source_messages(source_id: str, limit: int = 20) -> dict:
    source = db.get_source(source_id)
    if source is None:
        raise ApiError("SOURCE_NOT_FOUND", "Source introuvable.", 404)
    if not gateway.is_connected():
        raise not_connected()
    _fetch_and_store(source, min(max(limit, 1), 100))
    messages = db.list_messages(source_id, min(max(limit, 1), 100))
    for message in messages:
        message["channel_username"] = source["username"]
        message["channel_id"] = source["channel_id"]
    return {"messages": messages}


@app.post("/api/sources/{source_id}/sync", dependencies=[Depends(require_auth)])
def sync_one_source(source_id: str) -> dict:
    source = db.get_source(source_id)
    if source is None:
        raise ApiError("SOURCE_NOT_FOUND", "Source introuvable.", 404)
    if not gateway.is_connected():
        raise not_connected()
    fetched, new_messages = _fetch_and_store(source, 50)
    from datetime import datetime, timezone

    stamp = datetime.now(timezone.utc).isoformat()
    db.update_source(
        source_id,
        last_sync=stamp,
        analyzed_posts=source["analyzed_posts"] + fetched,
    )
    stats = db.get_stats()
    db.set_stats(
        analyzed_posts=stats["analyzed_posts"] + fetched,
        new_episodes=new_messages,
    )
    db.add_history(True, fetched, new_messages)
    return {"messages_fetched": fetched, "new_messages": new_messages}


# ---------------------------------------------------------------------------
# Statistiques & synchronisation globale
# ---------------------------------------------------------------------------


@app.get("/api/stats", dependencies=[Depends(require_auth)])
def stats() -> dict:
    return {"stats": db.get_stats(), "history": db.list_history()}


@app.post("/api/sync", dependencies=[Depends(require_auth)])
def sync_all() -> dict:
    if not gateway.is_connected():
        raise not_connected()
    from datetime import datetime, timezone

    total_fetched = 0
    total_new = 0
    sources = db.list_sources()
    stamp = datetime.now(timezone.utc).isoformat()
    for source in sources:
        if not source["sync_enabled"]:
            continue
        fetched, new_messages = _fetch_and_store(source, 50)
        total_fetched += fetched
        total_new += new_messages
        db.update_source(
            source["id"],
            last_sync=stamp,
            analyzed_posts=source["analyzed_posts"] + fetched,
        )
    stats = db.get_stats()
    db.set_stats(
        analyzed_posts=stats["analyzed_posts"] + total_fetched,
        new_episodes=total_new,
        last_sync=stamp,
    )
    db.add_history(True, total_fetched, total_new)
    return {"stats": db.get_stats(), "history": db.list_history()}
