# AnimeBox 📺

Application mobile **Android** (Flutter) qui transformera vos canaux Telegram d'animés en une
bibliothèque organisée : détection automatique des titres, saisons, épisodes, qualités et langues.

> **Étape actuelle : 2 — Épisodes, choix de qualité et lecteur vidéo** (données toujours mockées,
> sans Telegram ni backend).

## État du projet

| Fonctionnalité | État |
| --- | --- |
| Navigation basse persistante (Accueil / Recherche / Bibliothèque / Téléchargements / Profil) | ✅ |
| Accueil (carousel, 🔥 Nouveaux épisodes, ⭐ Mes animés, ▶ Continuer) | ✅ |
| Recherche (champ + 6 filtres) | ✅ |
| Fiche animé (onglets Épisodes / Détails, Favoris / Reprendre / Suivre) | ✅ |
| **Liste des épisodes** (bannière animé, saisons + spéciaux, tri, badges NOUVEAU) | ✅ |
| **Choix qualité / langue** (QualityOption, LanguageOption, actions simulées) | ✅ |
| **Lecteur vidéo** (contrôles, progression persistée, prochain épisode, lecture auto) | ✅ |
| Progression de lecture locale (« Reprendre à … ») | ✅ |
| Telegram, moteur Python, backend, streaming réel, téléchargement réel | ⏳ étapes suivantes |

## Parcours de navigation

```
Accueil → Fiche animé → Liste des épisodes (écran 4)
                      → Choix qualité/langue (écran 5) → Lecteur (écran 6)
Lecteur → Épisodes (retour à la liste) · Qualité (retour à l'écran 5) · Prochain épisode → écran 5
```

## Lancer le projet

```bash
# Prérequis : Flutter 3.47+ (Dart 3.13+), Android SDK, JDK 17

flutter pub get        # dépendances
flutter run            # lancer sur un appareil/émulateur Android
flutter test           # 30 tests (modèles, dépôt, navigation, épisodes, lecteur)
flutter analyze        # analyse statique (0 problème)
flutter build apk --debug   # APK de débogage
```

## Architecture

```
lib/
├── main.dart                     # Point d'entrée (injection du dépôt)
├── app/                          # Racine MaterialApp, thème, routes nommées (4 routes)
├── core/theme/                   # Palette sombre/violet + thème global
├── features/
│   ├── anime/data/
│   │   ├── models/               # Anime, Season, Episode, EpisodeQuality, VideoQuality,
│   │   │                         # LibraryEntry, PlaybackProgress, PlaybackSettings, SearchFilters
│   │   ├── mock/                 # Données de démonstration (4 animés, vignettes, tailles fictives)
│   │   └── repositories/         # Interface AnimeRepository + implémentation mockée notifiable
│   ├── home/                     # Accueil (héros, cartes, continuer)
│   ├── search/                   # Recherche + filtres
│   ├── details/                  # Fiche animé (onglets Épisodes / Détails)
│   ├── episodes/                 # ÉCRAN 4 — liste des épisodes (saisons, tri, spéciaux)
│   ├── quality/                  # ÉCRAN 5 — choix qualité + langue + actions
│   ├── player/                   # ÉCRAN 6 — lecteur + PlaybackController simulé
│   ├── library/                  # Bibliothèque (favoris, suivis)
│   ├── downloads/                # Placeholder Téléchargements
│   └── profile/                  # Placeholder Profil
├── navigation/                   # Coquille principale + barre de navigation basse
└── shared/widgets/               # Composants réutilisables (EpisodeCard, QualityOption,
                                  # LanguageOption, SeasonSelector, VideoControls, ActionButton,
                                  # PlayerProgressSlider, EpisodeThumbnail…)
```

### Points clés de l'étape 2

- **Structure des données** : un épisode regroupe ses qualités (`Episode.qualities` → `EpisodeQuality`
  avec qualité, résolution, taille mockée, langue, sous-titres, disponibilité). Aucune duplication
  d'épisode : 1080p/720p/480p/360p appartiennent au même épisode.
- **Progression de lecture** séparée de l'interface (`LibraryEntry.progressMap` +
  `AnimeRepository.recordProgress`) : prête à être persistée en base de données ; « Reprendre à … »
  alimente déjà l'accueil et le lecteur.
- **Lecteur** : `PlaybackController` simulé (ticker 500 ms, play/pause, seek ±10 s, barre glissable,
  plein écran via orientations) — remplaçable par un vrai player sans toucher aux écrans.
- **Lecture automatique** : structure prête (compte à rebours + bascule dans les paramètres), logique
  complexe volontairement différée.
- **Boutons Telegram / Téléchargement** : comportements simulés (SnackBar / feuille d'information),
  aucun vrai lien.
- **Modèles prêts pour Telegram** : la prochaine étape ajoutera `telegramMessageId`,
  `telegramChannelId`, `telegramMessageLink`, `fileId` à `EpisodeQuality` (non utilisés aujourd'hui).

## Prochaines étapes (à valider une par une)

1. Connexion Telegram + ajout de canaux comme sources
2. Moteur de détection (titre, saison, épisode, qualité, langue, sous-titres)
3. API backend + remplacement du dépôt mocké
4. Lecture réelle, téléchargement, notifications, synchronisation
