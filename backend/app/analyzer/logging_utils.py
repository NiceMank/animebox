"""Logs du moteur — utiles, jamais sensibles.

Règles strictes : aucun token, API_HASH, session Telegram, mot de passe ou
secret ne doit apparaître dans les journaux. ``redact`` sert de garde-fou
générique pour toute valeur qui passerait malgré tout.
"""

from __future__ import annotations

import logging
import re

# Motifs génériques de valeurs sensibles (défense en profondeur).
_SENSITIVE_PATTERNS = (
    re.compile(r"(?i)(api[_-]?hash|api[_-]?id)\s*[:=]\s*\S+"),
    re.compile(r"\b[0-9a-f]{64}\b"),  # empreintes/tokens hexadécimaux longs
    re.compile(r"(?i)password\s*[:=]\s*\S+"),
)

REDACTED = "***"


def redact(text: str) -> str:
    for pattern in _SENSITIVE_PATTERNS:
        text = pattern.sub(REDACTED, text)
    return text


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(f"animebox.{name}")
