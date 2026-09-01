"""Configuration du backend — lue exclusivement depuis les variables
d'environnement (aucun secret dans le code ni dans le dépôt).

Variables reconnues :
  TELEGRAM_API_ID      — API_ID de l'application Telegram (côté serveur).
  TELEGRAM_API_HASH    — API_HASH de l'application Telegram (côté serveur).
  TELEGRAM_MOCK        — « 1 » force le mode simulation locale.
  SESSION_DIR          — dossier des sessions Telegram (jamais commité).
  DB_PATH              — chemin de la base SQLite locale.
  TOKEN_TTL_DAYS       — durée de validité des jetons d'accès (défaut 30).
  UPLOADS_DIR          — dossier des photos de profil téléchargées.

Sans TELEGRAM_API_ID/API_HASH, le backend démarre automatiquement en
mode MOCK : tous les endpoints fonctionnent avec des données simulées,
ce qui permet de développer et tester l'application sans identifiants.
"""
import os

_BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TELEGRAM_API_ID = os.environ.get("TELEGRAM_API_ID", "").strip() or None
TELEGRAM_API_HASH = os.environ.get("TELEGRAM_API_HASH", "").strip() or None
TELEGRAM_MOCK = os.environ.get("TELEGRAM_MOCK", "0") == "1"

# Mode simulation si demandé explicitement OU si les identifiants manquent.
MOCK_MODE = TELEGRAM_MOCK or not TELEGRAM_API_ID or not TELEGRAM_API_HASH

SESSION_DIR = os.environ.get("SESSION_DIR", os.path.join(_BASE, ".sessions"))
DB_PATH = os.environ.get("DB_PATH", os.path.join(_BASE, "animebox.db"))
UPLOADS_DIR = os.environ.get("UPLOADS_DIR", os.path.join(_BASE, "uploads"))
TOKEN_TTL_DAYS = int(os.environ.get("TOKEN_TTL_DAYS", "30"))

# --- Métadonnées du catalogue (étape 6) -------------------------------------
# Aucune clé secrète requise : le fournisseur distant par défaut (Jikan,
# API publique de MyAnimeList) est accessible sans authentification. Si un
# futur fournisseur exige une clé, elle vivra dans METADATA_API_KEY
# (variable d'environnement serveur — jamais dans l'app ni le dépôt).
METADATA_PROVIDER = os.environ.get("METADATA_PROVIDER", "auto").strip().lower()
METADATA_TTL_DAYS = int(os.environ.get("METADATA_TTL_DAYS", "7"))
METADATA_REMOTE_BASE_URL = os.environ.get(
    "METADATA_REMOTE_BASE_URL", "https://api.jikan.moe/v4"
).rstrip("/")
METADATA_TIMEOUT_SECONDS = int(os.environ.get("METADATA_TIMEOUT_SECONDS", "10"))
METADATA_DOWNLOAD_IMAGES = os.environ.get("METADATA_DOWNLOAD_IMAGES", "1") == "1"
METADATA_API_KEY = os.environ.get("METADATA_API_KEY", "").strip() or None  # réservé

SESSION_FILE = os.path.join(SESSION_DIR, "account.session")

for _directory in (SESSION_DIR, UPLOADS_DIR, os.path.dirname(DB_PATH)):
    os.makedirs(_directory, exist_ok=True)
