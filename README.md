# AnimeBox

[![CI](https://github.com/NiceMank/animebox/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/NiceMank/animebox/actions/workflows/ci.yml)

Application mobile **Android** (Flutter) qui transforme vos canaux Telegram d'animés en une
bibliothèque organisée : détection automatique des titres, saisons, épisodes, qualités et langues.

> **Architecture actuelle : 100 % locale, sans AUCUN backend.** L'application dialogue directement avec
> Telegram (TDLib embarqué), analyse les publications sur l'appareil et stocke le catalogue dans
> une base SQLite locale. **Aucun serveur n'est requis.**

## État du projet

| Fonctionnalité | État |
| --- | --- |
| Navigation basse persistante (Accueil / Recherche / Bibliothèque / Téléchargements / Profil) | ✅ |
| Accueil, Recherche (6 filtres), Fiche animé, Épisodes, Qualité, Lecteur | ✅ |
| Bibliothèque complète (Favoris, Suivis, Continuer, Récents, Tous) | ✅ |
| Sources Telegram : liste, ajout avec vérification d'accessibilité, détails, suppression | ✅ |
| **Logo AnimeBox** (généré, embarqué) + **écran d'accueil animé** (cube bleu, balayage vers le haut → onboarding) | ✅ |
| Synchronisation (statistiques, historique, progression, annulation) | ✅ |
| **Connexion Telegram réelle depuis l'appareil** (numéro → code → 2FA → connecté) | ✅ |
| **Session restaurée automatiquement** (stockage chiffré TDLib + clé en Keystore) | ✅ |
| **Récupération paginée** (50 messages/page) + **synchronisation incrémentale** (curseur) | ✅ |
| **Moteur d'analyse local** (port Dart du moteur : titre, saison, épisode, qualité, langue) | ✅ |
| **Regroupement des qualités** (une fiche épisode, plusieurs versions, références Telegram) | ✅ |
| **Base locale SQLite** (sources, catalogue, versions, favoris, progression, historique) | ✅ |
| **Hors-ligne** : catalogue consultable, « Dernière synchronisation » conservée | ✅ |
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

## Intégration continue & releases (GitHub Actions)

| Workflow | Déclencheur | Contenu |
| --- | --- | --- |
| **CI** (`.github/workflows/ci.yml`) | push sur une branche, PR | Flutter : `analyze` + tests complets · Build APK **artefact** de test (client MTProto réel si les secrets `ANIMEBOX_TELEGRAM_API_ID/HASH` sont définis) |
| **Release** (`.github/workflows/release.yml`) | push d'un tag `v*` (ou manuel) | Vérifications complètes + build APK + **GitHub Release** publiée avec l'APK en pièce jointe |

Le wrapper Gradle est versionné (`android/gradlew`, `gradle-wrapper.jar`) : aucune installation
locale n'est nécessaire pour compiler. L'APK publié est signé avec les clés de débogage
(installable pour tester, pas pour le Play Store). Pour publier : `git tag v0.7.1 && git push origin v0.7.1`.

## Lancer l'application

```bash
flutter pub get

# Mode démonstration (aucun identifiant) : données mockées, tous les écrans.
flutter run

# Mode RÉEL local : Telegram direct depuis l'appareil (client MTProto).
# Obtenez api_id / api_hash sur https://my.telegram.org (compte développeur),
# puis lancez avec :
flutter run \
  --dart-define=ANIMEBOX_TELEGRAM_API_ID=123456 \
  --dart-define=ANIMEBOX_TELEGRAM_API_HASH=abcdef0123456789...

# Vérifications
flutter analyze          # 0 issue
flutter test             # modèles, moteur, services, écrans
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

## Aucun backend Telegram (décision d'architecture)

L'ancien mode « serveur API » (étapes 1-6 — FastAPI + Telethon, session utilisateur hébergée
sur un serveur) a été **entièrement supprimé** : il est incompatible avec l'exigence de
confidentialité (« aucune session utilisateur Telegram ne quitte l'appareil »). Le moteur
d'analyse a été porté en Dart : l'application est autonome, du scan des messages au catalogue.

## Confidentialité

Vos sources Telegram et votre catalogue sont traités localement sur votre appareil. AnimeBox ne
transmet ni votre session Telegram, ni vos messages, ni vos fichiers, ni aucune information
privée à un serveur distant (la section « Confidentialité » des réglages l'explique dans
l'application elle-même).

## Permissions Android

Seule la permission `INTERNET` est demandée (requise pour Telegram). Aucune autre permission
n'est sollicitée à l'installation ; les permissions éventuellement nécessaires au futur
téléchargement seront demandées au moment où elles deviendront nécessaires.
