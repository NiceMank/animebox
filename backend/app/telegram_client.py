"""Service Telegram du backend.

Deux implémentations derrière une même interface :

- RealTelegramService : Telethon (session utilisateur côté serveur).
  Utilisé uniquement lorsque TELEGRAM_API_ID / TELEGRAM_API_HASH sont
  fournis par variables d'environnement.
- MockTelegramService : simulation locale déterministe, utilisée quand
  aucun identifiant n'est configuré (développement, tests, démonstration).

Le client mobile ne dialogue jamais directement avec l'API Telegram :
il passe toujours par ce backend.
"""
import threading
import zlib
from datetime import datetime, timedelta, timezone

from . import config
from .errors import (
    ApiError,
    flood,
    invalid_code,
    not_connected,
    source_inaccessible,
    source_not_found,
    telegram_error,
    two_step_needed,
)

# ---------------------------------------------------------------------------
# Normalisation des saisies utilisateur
# ---------------------------------------------------------------------------

_USERNAME_RE = None


def normalize_input(raw: str) -> str:
    """Accepte `@username`, `https://t.me/username` ou `username`."""
    value = (raw or "").strip()
    if value.startswith("@"):
        value = value[1:]
    if value.startswith("http://") or value.startswith("https://"):
        value = value.rstrip("/").split("/")[-1].split("?")[0]
    if not value:
        raise ApiError("INVALID_INPUT", "Veuillez saisir une source.", 422)
    import re

    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{3,31}", value):
        raise ApiError("INVALID_INPUT", "Format de source invalide.", 422)
    return value


# ---------------------------------------------------------------------------
# Interface commune
# ---------------------------------------------------------------------------


class TelegramGateway:
    """Contrat implémenté par le service réel et le service simulé."""

    def send_code(self, phone: str) -> None:  # pragma: no cover - interface
        raise NotImplementedError

    def verify_code(self, phone: str, code: str) -> dict:  # pragma: no cover
        raise NotImplementedError

    def logout(self) -> None:  # pragma: no cover
        raise NotImplementedError

    def is_connected(self) -> bool:  # pragma: no cover
        raise NotImplementedError

    def current_user(self) -> dict | None:  # pragma: no cover
        raise NotImplementedError

    def resolve(self, username: str) -> dict:  # pragma: no cover
        raise NotImplementedError

    def fetch_messages(self, username: str, channel_id, limit: int) -> list[dict]:  # pragma: no cover
        raise NotImplementedError


# ---------------------------------------------------------------------------
# Service réel (Telethon)
# ---------------------------------------------------------------------------


class RealTelegramService(TelegramGateway):
    def __init__(self) -> None:
        # Import tardif : le module ne charge Telethon qu'en mode réel.
        from telethon.sync import TelegramClient

        self._client = TelegramClient(
            config.SESSION_FILE, int(config.TELEGRAM_API_ID), config.TELEGRAM_API_HASH
        )
        self._lock = threading.Lock()
        self._phone_code_hash: dict[str, str] = {}

    def _call(self, function):
        with self._lock:
            try:
                return function()
            except ApiError:
                raise
            except Exception as error:  # noqa: BLE001 - normalisation
                self._map_telethon_error(error)

    def _map_telethon_error(self, error: Exception) -> None:
        from telethon import errors as tg_errors

        name = type(error).__name__
        if name == "UsernameNotOccupiedError":
            raise source_not_found() from error
        if name in ("ChannelPrivateError", "ChatAdminRequiredError"):
            raise source_inaccessible() from error
        if name == "PhoneCodeInvalidError":
            raise invalid_code() from error
        if name == "PhoneCodeExpiredError":
            raise ApiError("PHONE_CODE_EXPIRED", "Le code a expiré. Renvoyez un nouveau code.", 400) from error
        if name == "SessionPasswordNeededError":
            raise two_step_needed() from error
        if name == "FloodWaitError":
            seconds = int(getattr(error, "seconds", 60))
            raise flood(seconds) from error
        if isinstance(error, tg_errors.RPCError):
            raise telegram_error(f"{error.__class__.__name__}") from error
        raise telegram_error("Connexion impossible au service Telegram.") from error

    def send_code(self, phone: str) -> None:
        def go():
            if not self._client.is_connected():
                self._client.connect()
            sent = self._client.send_code_request(phone)
            self._phone_code_hash[phone] = sent.phone_code_hash

        self._call(go)

    def verify_code(self, phone: str, code: str) -> dict:
        def go():
            if not self._client.is_connected():
                self._client.connect()
            me = self._client.sign_in(
                phone, code, phone_code_hash=self._phone_code_hash.get(phone, "")
            )
            return _user_from_entity(me)

        return self._call(go)

    def logout(self) -> None:
        def go():
            try:
                if self._client.is_connected():
                    self._client.log_out()
            finally:
                self._client.disconnect()

        self._call(go)

    def is_connected(self) -> bool:
        def go():
            if not self._client.is_connected():
                self._client.connect()
            return self._client.is_user_authorized()

        try:
            return bool(self._call(go))
        except ApiError:
            return False

    def current_user(self) -> dict | None:
        if not self.is_connected():
            return None
        return _user_from_entity(self._client.get_me())

    def resolve(self, username: str) -> dict:
        def go():
            entity = self._client.get_entity(username)
            from telethon.tl.types import Channel, Chat

            if not isinstance(entity, (Channel, Chat)):
                raise ApiError(
                    "INVALID_SOURCE_TYPE",
                    "Cette source n'est ni un canal ni un groupe.",
                    422,
                )
            return {
                "channel_id": entity.id,
                "username": getattr(entity, "username", None) or username,
                "title": entity.title,
                "description": getattr(entity, "about", None) or None,
                "kind": "channel" if entity.broadcast else "group",
            }

        return self._call(go)

    def fetch_messages(self, username: str, channel_id, limit: int) -> list[dict]:
        def go():
            entity = self._client.get_entity(username)
            raw = self._client.get_messages(entity, limit=limit)
            messages = []
            for message in raw or []:
                if message is None:
                    continue
                media_type = _media_type(message)
                messages.append(
                    {
                        "message_id": message.id,
                        "date": (message.date or datetime.now(timezone.utc)).isoformat(),
                        "text": (message.message or "").strip() or None,
                        "media_type": media_type,
                        "file_name": getattr(getattr(message, "file", None), "name", None),
                        "file_size": getattr(getattr(message, "file", None), "size", None),
                        "link": _message_link(message.id, username, channel_id),
                    }
                )
            return messages

        return self._call(go)


def _user_from_entity(user) -> dict:
    return {
        "first_name": getattr(user, "first_name", None) or "Utilisateur",
        "last_name": getattr(user, "last_name", None),
        "username": getattr(user, "username", None),
        "phone": getattr(user, "phone", None),
    }


def _media_type(message) -> str:
    if getattr(message, "video", None) is not None:
        return "video"
    if getattr(message, "photo", None) is not None:
        return "image"
    if getattr(message, "document", None) is not None:
        return "document"
    return "text"


def _message_link(message_id: int, username: str, channel_id) -> str | None:
    """Construit un lien t.me uniquement quand Telegram le permet.

    - canaux publics : https://t.me/{username}/{message_id}
    - canaux privés accessibles : https://t.me/c/{channel_id}/{message_id}
    """
    if username:
        return f"https://t.me/{username}/{message_id}"
    if channel_id:
        return f"https://t.me/c/{channel_id}/{message_id}"
    return None


# ---------------------------------------------------------------------------
# Service simulé (développement / tests)
# ---------------------------------------------------------------------------


class MockTelegramService(TelegramGateway):
    """Simulation locale déterministe — aucune requête réseau."""

    _DEMO_USER = {
        "first_name": "Démo",
        "last_name": "AnimeBox",
        "username": "animebox_demo",
        "phone": None,
    }

    _CAPTIONS = [
        ("Solo Leveling S02E08 1080p VF", "video", 1_288_490_188, "solo-leveling-s02e08-1080p.mkv"),
        ("Solo Leveling S02E08 720p VF", "video", 697_932_185, "solo-leveling-s02e08-720p.mkv"),
        ("Solo Leveling S02E08 480p VOSTFR", "video", 375_809_638, "solo-leveling-s02e08-480p.mkv"),
        ("One Piece 1124 720p VOSTFR", "video", 644_245_094, "one-piece-1124-720p.mkv"),
        ("Jujutsu Kaisen S02E17 1080p VF", "video", 1_180_591_620, "jujutsu-kaisen-s02e17.mkv"),
        ("Demon Slayer S04E07 1080p VOSTFR", "video", 1_288_490_188, "demon-slayer-s04e07.mkv"),
        ("Solo Leveling S02E09 1080p VF", "video", 1_288_490_188, "solo-leveling-s02e09.mkv"),
        ("One Piece 1125 1080p VOSTFR", "document", 1_073_741_824, "one-piece-1125.mkv"),
    ]

    # Flux spécifiques pour le scénario multi-sources (étape 6) : deux
    # canaux publient des qualités différentes du même épisode.
    _CAPTIONS_BY_USER = {
        "sourcea": (
            ("Solo Leveling S02E08 1080p VF", "video", 1_288_490_188, "solo-leveling-s02e08-1080p.mkv"),
            ("Solo Leveling S02E08 720p VF", "video", 697_932_185, "solo-leveling-s02e08-720p.mkv"),
        ),
        "sourceb": (
            ("Solo Leveling S02E08 480p VOSTFR", "video", 375_809_638, "solo-leveling-s02e08-480p.mkv"),
        ),
    }

    def __init__(self) -> None:
        self._connected = True  # la simulation démarre « connectée »

    def send_code(self, phone: str) -> None:
        pass

    def verify_code(self, phone: str, code: str) -> dict:
        if len(code.strip()) != 5:
            raise invalid_code()
        self._connected = True
        return dict(self._DEMO_USER)

    def logout(self) -> None:
        self._connected = False

    def is_connected(self) -> bool:
        return self._connected

    def current_user(self) -> dict | None:
        return dict(self._DEMO_USER) if self._connected else None

    def resolve(self, username: str) -> dict:
        username = normalize_input(username)
        if username == "introuvable":
            raise source_not_found()
        if username == "prive":
            raise source_inaccessible()
        title = " ".join(part.capitalize() for part in username.replace("_", " ").split())
        return {
            "channel_id": zlib.crc32(username.encode()),
            "username": username,
            "title": title,
            "description": f"Canal de démonstration AnimeBox (@{username}).",
            "kind": "channel",
        }

    def fetch_messages(self, username: str, channel_id, limit: int) -> list[dict]:
        now = datetime.now(timezone.utc)
        captions = self._CAPTIONS_BY_USER.get(normalize_input(username), self._CAPTIONS)
        base_id = {
            "sourcea": 50001,
            "sourceb": 60001,
        }.get(normalize_input(username), 12345)
        messages = []
        for index, (caption, media_type, size, file_name) in enumerate(captions[:limit]):
            link = (
                f"https://t.me/{username}/{base_id - index}"
                if index < len(captions) - 1
                else None  # dernier message : pas de lien (bouton désactivé côté client)
            )
            messages.append(
                {
                    "message_id": base_id - index,
                    "date": (now - timedelta(hours=index * 5)).isoformat(),
                    "text": caption,
                    "media_type": media_type,
                    "file_name": file_name,
                    "file_size": size,
                    "link": link,
                }
            )
        return messages


def build_gateway() -> TelegramGateway:
    if config.MOCK_MODE:
        return MockTelegramService()
    return RealTelegramService()
