# AnimeBox 📺

[![CI](https://github.com/NiceMank/animebox/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/NiceMank/animebox/actions/workflows/ci.yml)

**Votre bibliothèque d'animés, alimentée par vos propres canaux Telegram.**

AnimeBox est une application **Android** (Flutter) qui transforme les chaînes Telegram
de partage d'animés en un catalogue propre et organisé : titres, saisons, épisodes,
qualités et langues détectés automatiquement — le tout **100 % sur votre appareil**.

> 🔒 **Zéro serveur. Zéro backend.** L'application parle directement à Telegram
> (TDLib embarqué), analyse les publications localement et stocke le catalogue dans
> une base SQLite sur le téléphone. Aucune donnée ne transite par un serveur tiers.

---

## ✨ Fonctionnalités

| Fonctionnalité | État |
| --- | --- |
| Écran d'accueil animé (logo, cube 3D, balayage vers le haut) + onboarding | ✅ |
| Navigation basse persistante (Accueil / Recherche / Bibliothèque / Téléchargements / Profil) | ✅ |
| Accueil, Recherche (6 filtres), Fiche animé, Épisodes, Sélecteur de qualité, Lecteur (libmpv : MKV, sous-titres, pistes audio) | ✅ |
| Bibliothèque complète (Favoris, Suivis, Continuer, Récents, Tous) | ✅ |
| Thème personnalisable | ✅ |
| **Connexion Telegram réelle** (numéro → code → 2FA) via MTProto | ✅ |
| **Session restaurée automatiquement** — base TDLib chiffrée, clé dans le Keystore Android | ✅ |
| Sources Telegram : ajout avec vérification d'accessibilité, détails, suppression | ✅ |
| **Moteur d'analyse local** : détection titre, saison, épisode, qualité, langue | ✅ |
| **Regroupement des qualités** : une fiche épisode, plusieurs versions liées à Telegram | ✅ |
| **Synchronisation paginée + incrémentale** (seuls les nouveaux messages) | ✅ |
| **Base SQLite locale** (sources, catalogue, versions, favoris, progression, historique) | ✅ |
| **Mode hors-ligne** : catalogue consultable, date de dernière synchronisation | ✅ |
| Notifications locales (nouveaux épisodes) + synchronisation en arrière-plan (WorkManager) | ✅ |
| Téléchargement réel des vidéos, streaming | ⏳ prochaines étapes |

## 🏗️ Architecture

```
TÉLÉPHONE (aucun serveur distant)
   │
   ▼
ANIMEBOX (Flutter)
   ├─ TdlibTelegramGateway ──► TDLib embarqué (libtdjson.so) ──► serveurs Telegram
   │      connexion · code · 2FA · canaux · messages paginés
   │
   ├─ LocalSyncService
   │      messages → RuleBasedAnalyzer (moteur Dart)
   │      → classement → LocalDatabase (SQLite)
   │        sources · animés · saisons · épisodes · versions
   │        favoris · progression · historique
   │
   └─ LocalAnimeRepository ──► catalogue affiché dans l'application
```

**Principes non négociables**

- 🔐 La session Telegram **ne quitte jamais l'appareil** : base de session chiffrée,
  clé générée et conservée dans le stockage sécurisé Android (Keystore).
- 🔑 Les identifiants d'application (`api_id` / `api_hash` de
  [my.telegram.org](https://my.telegram.org)) sont injectés **à la compilation
  uniquement** — jamais codés en dur, jamais journalisés, jamais dans le dépôt.
- 🚫 Aucun proxy, aucune API maison, aucun stockage central. L'ancien backend
  a été entièrement supprimé du projet.

## 🚀 Installation (APK)

1. Allez dans **Actions** → dernier run vert sur `main` → artefact **AnimeBox-APK**
   (ou dans **Releases** si un tag `v*` a été publié).
2. Téléchargez et dézippez l'artefact, transférez l'APK sur le téléphone.
3. **Désinstallez toute version précédente** (signature de débogage différente à
   chaque build — Android bloque la mise à jour directe par mesure de sécurité).
4. Installez l'APK, ouvrez AnimeBox.

**Première connexion Telegram** : Profil → *Connexion Telegram* → numéro au format
international (**+…**) → code reçu par Telegram → (mot de passe 2FA si activé) → connecté.

## 🛠️ Développement

```bash
flutter pub get

# Mode démonstration (aucun identifiant requis) : données mockées, tous les écrans.
flutter run

# Mode RÉEL : client MTProto direct depuis l'appareil.
# api_id / api_hash : https://my.telegram.org (section API development tools).
flutter run \
  --dart-define=ANIMEBOX_TELEGRAM_API_ID=123456 \
  --dart-define=ANIMEBOX_TELEGRAM_API_HASH=abcdef0123456789...

# Vérifications
flutter analyze          # 0 issue
flutter test             # 254 tests : modèles, moteur, services, écrans, fiabilité TDLib
flutter build apk --debug
```

Le wrapper Gradle est versionné (`android/gradlew`, `gradle-wrapper.jar`) : aucune
installation locale supplémentaire n'est nécessaire pour compiler.

## 🔄 Intégration continue & releases

| Workflow | Déclencheur | Contenu |
| --- | --- | --- |
| **CI** (`.github/workflows/ci.yml`) | push sur branche, PR, `main` | `flutter analyze` + suite de tests complète + build **APK en artefact** (client MTProto réel via les secrets `ANIMEBOX_TELEGRAM_API_ID` / `ANIMEBOX_TELEGRAM_API_HASH`) |
| **Release** (`.github/workflows/release.yml`) | tag `v*` (ou manuel) | Vérifications + APK publié en **GitHub Release** |

Les APK sont signés avec les clés de débogage : installables pour tester,
pas destinés au Play Store. Publier une release :

```bash
git tag v0.9.1 && git push origin v0.9.1
```

## 🔐 Permissions Android

Seule la permission `INTERNET` est demandée (requise pour Telegram). Aucune autre
permission n'est sollicitée à l'installation ; celles qui deviendraient nécessaires
(ex. stockage pour les futurs téléchargements) seront demandées au moment voulu.

## 📁 Structure du projet

```
lib/
├── main.dart                  # Point d'entrée
├── app/  core/  navigation/  shared/
└── features/
    ├── intro/                 # Écran d'accueil animé (logo, balayage)
    ├── onboarding/            # Premier lancement
    ├── home/  search/  library/  downloads/  profile/
    ├── details/  episodes/  quality/  player/  media/
    ├── telegram/              # Gateway TDLib, connexion, sources
    ├── sync/  local/  analyzer/   # Moteur d'analyse + base SQLite
    ├── settings/  notifications/
android/                       # Projet Android (wrapper Gradle versionné)
assets/                        # Logo, visuels, polices Poppins
test/                          # Suite de tests (step1 → step16)
.github/workflows/             # CI + Release
```

## 🗺️ Feuille de route

- [ ] Téléchargement réel des vidéos (avec progression et reprise)
- [ ] Streaming direct depuis Telegram
- [ ] Notifications enrichies (fin de téléchargement)
- [ ] Publication signée (clé de release) pour mises à jour en douceur

---

*AnimeBox — vos canaux Telegram, votre bibliothèque, votre appareil. C'est tout.*
