"""Cache d'images du catalogue (posters / backdrops).

Les images distantes sont téléchargées une seule fois, redimensionnées
localement (tailles adaptées aux usages mobile), puis servies par le
backend. Objectifs : ne pas re-télécharger de grandes ressources, limiter
la consommation mobile, rester fonctionnel si la source d'images est
indisponible.

Sécurité : seuls les hôtes d'images autorisés sont acceptés (aucun proxy
ouvert), taille maximale limitée, noms de fichiers validés.
"""

from __future__ import annotations

import hashlib
import logging
import os
import re

import httpx

from .. import config

logger = logging.getLogger("animebox.metadata.images")

_ALLOWED_HOSTS = {"cdn.myanimelist.net", "image.tmdb.org", "img1.ak.crunchyroll.com"}
_MAX_BYTES = 8 * 1024 * 1024
_TIMEOUT = 12.0

# Poster 600x900, backdrop 1280x720, miniature 300x450.
_SIZES = {"poster": (600, 900), "backdrop": (1280, 720), "thumb": (300, 450)}

_FILENAME_RE = re.compile(r"^[a-f0-9]{16}\.(poster|backdrop|thumb)\.jpg$")


def images_dir() -> str:
    directory = os.path.join(config.UPLOADS_DIR, "images")
    os.makedirs(directory, exist_ok=True)
    return directory


def valid_filename(name: str) -> bool:
    return bool(_FILENAME_RE.match(name))


def cache_and_resize(url: str, kind: str) -> str | None:
    """Télécharge, redimensionne et met en cache une image distante.

    Renvoie le nom du fichier local (servi via /api/assets/images/…) ou
    None si l'image est indisponible (jamais bloquant).
    """
    if kind not in _SIZES or not url:
        return None
    if not url.startswith(("http://", "https://")):
        return None
    host = url.split("/")[2] if "/" in url[8:] else ""
    if host not in _ALLOWED_HOSTS:
        logger.info("[Images] hôte non autorisé : %s", host)
        return None
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]
    filename = f"{digest}.{kind}.jpg"
    path = os.path.join(images_dir(), filename)
    if os.path.exists(path):
        return filename

    try:
        response = httpx.get(url, timeout=_TIMEOUT, follow_redirects=True)
        response.raise_for_status()
    except httpx.HTTPError as error:
        logger.warning("[Images] téléchargement impossible (%s) : %s", host, type(error).__name__)
        return None
    content = response.content
    if not content or len(content) > _MAX_BYTES:
        logger.warning("[Images] contenu invalide ou trop volumineux (%s)", url)
        return None
    try:
        _resize_save(content, path, *_SIZES[kind])
    except Exception:  # noqa: BLE001 - Pillow peut manquer : on garde l'original
        with open(path, "wb") as handle:
            handle.write(content)
    return filename


def _resize_save(content: bytes, path: str, width: int, height: int) -> None:
    from io import BytesIO

    from PIL import Image

    with Image.open(BytesIO(content)) as image:
        image = image.convert("RGB")
        ratio = max(width / image.width, height / image.height)
        resized = image.resize(
            (max(width, round(image.width * ratio)), max(height, round(image.height * ratio))),
            Image.LANCZOS,
        )
        left = (resized.width - width) // 2
        top = (resized.height - height) // 2
        resized.crop((left, top, left + width, top + height)).save(
            path, "JPEG", quality=84, optimize=True
        )
