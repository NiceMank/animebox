"""Authentification par jeton Bearer — partagée entre les routes API
principales et les routes du moteur d'analyse.
"""

from fastapi import Header

from . import db
from .errors import unauthorized


def require_auth(authorization: str | None = Header(default=None)) -> None:
    if not authorization or not authorization.startswith("Bearer "):
        raise unauthorized()
    token = authorization.removeprefix("Bearer ").strip()
    if not db.token_exists(token):
        raise unauthorized()
