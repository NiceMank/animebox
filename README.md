# AnimeBox

Application mobile **Android** (Flutter) qui transforme vos canaux Telegram d'animés en une
bibliothèque organisée : détection automatique des titres, saisons, épisodes, qualités et langues.

> **Étape actuelle : 7 — Architecture 100 % locale.** L'application dialogue directement avec
> Telegram (TDLib embarqué), analyse les publications sur l'appareil et stocke le catalogue dans
> une base SQLite locale. **Aucun serveur n'est requis.**

## État du projet

| Fonctionnalité | État |
| --- | --- |
| Navigation basse persistante (Accueil / Recherche / Bibliothèque / Téléchargements / Profil) | ✅ |
| Accueil, Recherche (6 filtres), Fiche animé, Épisodes, Qualité, Lecteur | ✅ |
| Bibliothèque complète (Favoris, Suivis, Continuer, Récents, Tous) | ✅ |
| Sources Telegram : liste, ajout avec vérification d'accessibilité, détails, suppression | ✅ |
| Synchronisation (statistiques, historique, progression, annulation) | ✅ |
| **Connexion Telegram réelle depuis l'appareil** (numéro → code → 2FA → connecté) | ✅ |
| **Session restaurée automatiquement** (stockage chiffré TDLib + clé en Keystore) | ✅ |
| **Récupération paginée** (50 messages/page) + **synchronisation incrémentale** (curseur) | ✅ |
| **Moteur d'analyse local** (port Dart du moteur : titre, saison, épisode, qualité, langue) | ✅ |
| **Regroupement des qualités** (une fiche épisode, plusieurs versions, références Telegram) | ✅ |
| **Base locale SQLite** (sources, catalogue, versions, favoris, progression, historique) | ✅ |
| **Hors-ligne** : catalogue consultable, « Dernière synchronisation » conservée | ✅ |
| Métadonnées enrichies côté backend (étape 6, mode hérité) | ✅ (mode `--dart-define=ANIMEBOX_API_URL=…`) |
| Téléchargement réel, streaming, notifications | ⏳ étapes suivantes |

## Architecture (étape 7 — locale)

```
TÉLÉPHONE
   ↓
ANIMEBOX (Flutter)
   ├─ TdlibTelegramGateway ──► TDLib embarqué (libtdjson.so) ──► serveurs Telegram
   │      connect / code / 2FA / canaux / messages paginés
   ├─ LocalSyncService : messages → RuleBasedAnalyzer (moteur Dart)
   │      → classement → LocalDatabase (SQLite : sources, anime, saisons,
   │        épisodes, versions, favoris, progression, historique)
   └─ LocalAnimeRepository : catalogue affiché dans l'application
```

- **Aucun serveur distant** : ni Vercel, ni API, ni proxy, ni stockage central. La session
  Telegram, les messages et le catalogue restent sur l'appareil.
- **Session sensible** : la base de session de TDLib est chiffrée (clé générée et conservée
  dans le stockage sécurisé Android — Keystore), jamais dans les préférences classiques.
- **Identifiants d'application** (my.telegram.org) : fournis à la compilation uniquement,
  jamais codés en dur, jamais journalisés, jamais envoyés.

## Lancer l'application

```bash
flutter pub get

# Mode démonstration (aucun identifiant) : données mockées, tous les écrans.
flutter run

# Mode RÉEL local : Telegram direct depuis l'appareil.
# Obtenez api_id / api_hash sur https://my.telegram.org (compte développeur),
# puis lancez avec :
flutter run \
  --dart-define=ANIMEBOX_TELEGRAM_API_ID=123456 \
  --dart-define=ANIMEBOX_TELEGRAM_API_HASH=abcdef0123456789...

# Mode backend hérité (étapes 1-6), optionnel :
flutter run --dart-define=ANIMEBOX_API_URL=http://10.0.2.2:8000

# Vérifications
flutter analyze          # 0 issue
flutter test             # 121 tests (modèles, moteur, services, écrans)
flutter build apk --debug
flutter build web
```

## Test réel (compte Telegram de test)

1. `flutter run` avec vos `--dart-define` (voir plus haut).
2. Profil → **Connexion Telegram** → numéro → code reçu → (2FA le cas échéant) → Connecté.
3. **Mes sources** → ajouter `@username` (ou un lien `t.me/…`) → aperçu → Ajouter.
   Un canal inaccessible affiche « Ce canal n'est pas accessible avec ce compte Telegram. »
4. **Synchroniser maintenant** : récupération paginée → analyse locale → catalogue mis à jour.
   Les synchronisations suivantes sont incrémentales (seuls les nouveaux messages).
5. Bibliothèque : les épisodes détectés apparaissent (versions multiples regroupées,
   « Ouvrir dans Telegram » renvoie vers la publication d'origine quand le lien existe).

## Backend (héritage des étapes 1-6 — conservé pour référence et tests)

Le dossier `backend/` (FastAPI + moteur Python + tests 159/159 + smoke_test 41/41) reste dans le
dépôt : il a servi de référence pour le port Dart du moteur d'analyse et reste utilisable via
`--dart-define=ANIMEBOX_API_URL=…`. Le fonctionnement normal de l'application n'en dépend plus.

```bash
cd backend
pip install -r requirements.txt
TELEGRAM_MOCK=1 uvicorn app.main:app --host 0.0.0.0 --port 8000
python3 smoke_test.py        # 41 vérifications
python3 -m pytest tests -q   # 159 tests
```

## Confidentialité

Vos sources Telegram et votre catalogue sont traités localement sur votre appareil. AnimeBox ne
transmet ni votre session Telegram, ni vos messages, ni vos fichiers, ni aucune information
privée à un serveur distant (la section « Confidentialité » des réglages l'explique dans
l'application elle-même).

## Permissions Android

Seule la permission `INTERNET` est demandée (requise pour Telegram). Aucune autre permission
n'est sollicitée à l'installation ; les permissions éventuellement nécessaires au futur
téléchargement seront demandées au moment où elles deviendront nécessaires.
