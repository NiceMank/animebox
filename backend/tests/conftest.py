"""Configuration pytest du backend.

Isolation : variables d'environnement positionnées AVANT tout import de
l'application (mode mock, base SQLite temporaire). Le chemin du backend
est ajouté à sys.path pour importer le package `app`.
"""

import os
import sys
import tempfile
from pathlib import Path

_TMP = tempfile.mkdtemp(prefix="animebox_tests_")
os.environ["TELEGRAM_MOCK"] = "1"
os.environ["DB_PATH"] = os.path.join(_TMP, "test.db")
os.environ["SESSION_DIR"] = os.path.join(_TMP, "sessions")

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

import pytest  # noqa: E402

from app.analyzer.aliases import AliasRegistry  # noqa: E402
from app.analyzer.engine import RuleBasedAnalyzer  # noqa: E402


@pytest.fixture()
def registry() -> AliasRegistry:
    return AliasRegistry()


@pytest.fixture()
def engine() -> RuleBasedAnalyzer:
    return RuleBasedAnalyzer()


@pytest.fixture()
def fresh_analyzer_db():
    """Vide les tables du moteur puis réinitialise (catalogue intégré reseedé)."""
    from app.analyzer import storage

    storage.init_schema()  # crée les tables si besoin
    with storage._connect() as connection:  # noqa: SLF001
        for table in (
            "episode_version",
            "episode",
            "season",
            "anime_alias",
            "anime",
            "analyzed_messages",
            "analyzer_jobs",
        ):
            connection.execute(f"DELETE FROM {table}")
    storage.init_schema()
    yield storage
