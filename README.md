# AnimeBox 📺

Application mobile **Android** (Flutter) qui transformera vos canaux Telegram d'animés en une
bibliothèque organisée : détection automatique des titres, saisons, épisodes, qualités et langues.

> **Étape actuelle : 4 — Intégration réelle de Telegram** (backend API + service Telegram
> côté serveur ; le moteur d'analyse intelligent viendra ensuite).

## État du projet

| Fonctionnalité | État |
| --- | --- |
| Navigation basse persistante (Accueil / Recherche / Bibliothèque / Téléchargements / Profil) | ✅ |
| Accueil, Recherche (6 filtres), Fiche animé, Épisodes, Qualité, Lecteur | ✅ |
| Bibliothèque complète (Favoris, Suivis, Continuer, Récents, Tous) | ✅ |
| Sources Telegram : liste, ajout avec vérification, détails, auto-sync, suppression | ✅ |
| Synchronisation (statistiques, historique, progression) | ✅ |
| **Connexion Telegram** (numéro → code → compte connecté, session expirée, erreurs) | ✅ |
| **Backend API** (FastAPI) : authentification par jeton, sources persistées (SQLite) | ✅ |
| **Service Telegram serveur** (Telethon) + mode simulation sans identifiants | ✅ |
| **Publications récentes** (IDs, dates, médias, liens t.me — écran de vérification) | ✅ |
| Moteur d'analyse (titre/saison/épisode/qualité), regroupement final, téléchargement | ⏳ étapes suivantes |

## Architecture Telegram

```
Application mobile (Flutter)          Backend API (FastAPI, backend/)        Telegram
────────────────────────────          ────────────────────────────────       ────────
ApiTelegramService ────HTTPS────►  /api/telegram/*  (code, session)   ──►  Telethon
                                 /api/sources/*    (résolution, CRUD)      (session serveur,
                                 /api/sources/{id}/messages                API_ID/API_HASH
                                 /api/sync, /api/stats                     en variables d'env)
```

- **Aucun secret côté mobile** : l'application ne contient ni API_ID, ni API_HASH, ni session
  Telegram en clair. Le jeton d'accès est stocké dans le **stockage sécurisé** de la plateforme
  (Keystore Android via `flutter_secure_storage`) ; `access_hash` n'est jamais envoyé au client.
- **Deux modes** : sans identifiants, le backend démarre en **mode simulation** (tous les
  endpoints fonctionnent avec des données locales) ; avec `TELEGRAM_API_ID`/`TELEGRAM_API_HASH`,
  il utilise **Telethon** pour la vraie connexion.
- L'application utilise le backend si elle est lancée avec
  `--dart-define=ANIMEBOX_API_URL=http://IP:8000`, sinon le service simulé local.

## Lancer le projet

```bash
# Application (mode démonstration locale par défaut)
flutter pub get
flutter run                       # Android
flutter test                      # 62 tests
flutter analyze

# Application branchée sur le backend :
flutter run --dart-define=ANIMEBOX_API_URL=http://10.0.2.2:8000   # émulateur Android

# Backend (depuis backend/)
pip install -r requirements.txt
TELEGRAM_MOCK=1 uvicorn app.main:app --host 0.0.0.0 --port 8000    # simulation (tests/démo)
# ou, avec de vrais identifiants (jamais commités) :
TELEGRAM_API_ID=... TELEGRAM_API_HASH=... uvicorn app.main:app --port 8000
python3 smoke_test.py             # 28 vérifications du parcours complet
```

## Variables d'environnement du backend (aucun secret dans le dépôt)

| Variable | Rôle | Défaut |
| --- | --- | --- |
| `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` | Identifiants de l'app Telegram (serveur uniquement) | absents → mode simulation |
| `TELEGRAM_MOCK` | `1` force le mode simulation | auto |
| `SESSION_DIR` | Dossier de la session Telethon (hors dépôt, `.gitignore`) | `backend/.sessions/` |
| `DB_PATH` | Base SQLite locale (sources, publications, stats, jetons) | `backend/animebox.db` |
| `UPLOADS_DIR` | Photos de profil téléchargées | `backend/uploads/` |
| `TOKEN_TTL_DAYS` | Durée de vie des jetons d'accès | 30 |

## Endpoints du backend

- `GET /health` — état + mode (mock/telegram)
- `POST /api/telegram/send-code` · `POST /api/telegram/verify-code` — connexion (retourne un jeton)
- `GET /api/telegram/status` · `POST /api/telegram/logout` — session (Bearer requis)
- `GET /api/sources` · `POST /api/sources` · `POST /api/sources/resolve` — sources persistées
- `PATCH /api/sources/{id}` (auto-sync) · `DELETE /api/sources/{id}` — gestion
- `GET /api/sources/{id}/messages` — publications récentes (ID, date, texte, média, lien t.me)
- `POST /api/sources/{id}/sync` · `POST /api/sync` · `GET /api/stats` — synchronisation

Erreurs normalisées : `{"error": {"code": "SOURCE_NOT_FOUND", "message": "…"}}`
(SOURCE_NOT_FOUND, SOURCE_INACCESSIBLE, PHONE_CODE_INVALID, UNAUTHORIZED, FLOOD, …).

## Structure du projet

```
lib/
├── app/                    # Racine, thème, routes (11 routes nommées)
├── core/                   # Thème, formats
├── features/
│   ├── anime/              # Modèles, données mockées, dépôt
│   ├── home/ search/ details/ episodes/ quality/ player/ library/
│   ├── telegram/
│   │   ├── data/
│   │   │   ├── models/     # TelegramSource, TelegramUser, TelegramMessage,
│   │   │   │               # ResolvedChannel, SyncStats/Progress/History, ApiException
│   │   │   └── services/
│   │   │       ├── telegram_service.dart        # Contrat (écrans ← interface)
│   │   │       ├── mock_telegram_service.dart   # Simulation locale
│   │   │       ├── api_telegram_service.dart    # Client HTTP du backend
│   │   │       ├── telegram_session_service.dart + secure_session_service.dart
│   │   │       └── episode_grouping_service.dart
│   │   └── screens/        # Sources, ajout, détail, synchronisation,
│   │                       # connexion Telegram, publications récentes
│   ├── downloads/ profile/
├── navigation/             # Coquille + navigation basse
└── shared/widgets/         # Composants réutilisables
backend/
├── app/                    # FastAPI : config, db, errors, telegram_client, main
├── requirements.txt
└── smoke_test.py           # 28 vérifications du parcours (sans identifiants)
```

## Prochaines étapes (à valider une par une)

1. Moteur d'analyse des publications (titre, saison, épisode, qualité, langue)
2. Regroupement final des épisodes dans la base de données
3. Catalogue alimenté par le backend (remplacement des données mockées)
4. Téléchargement réel, notifications, lecture
