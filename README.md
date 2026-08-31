# AnimeBox 📺

Application mobile **Android** (Flutter) qui transformera vos canaux Telegram d'animés en une
bibliothèque organisée : détection automatique des titres, saisons, épisodes, qualités et langues.

> **Étape actuelle : 3 — Sources Telegram (mock), synchronisation simulée et bibliothèque**
> (toujours sans API Telegram réelle ni backend).

## État du projet

| Fonctionnalité | État |
| --- | --- |
| Navigation basse persistante (Accueil / Recherche / Bibliothèque / Téléchargements / Profil) | ✅ |
| Accueil (carousel, 🔥 Nouveaux épisodes, ⭐ Mes animés, ▶ Continuer) | ✅ |
| Recherche (champ + 6 filtres) | ✅ |
| Fiche animé (onglets Épisodes / Détails, Favoris / Reprendre / Suivre) | ✅ |
| Liste des épisodes (saisons + spéciaux, tri, badges NOUVEAU) | ✅ |
| Choix qualité / langue (QualityOption, LanguageOption, actions simulées) | ✅ |
| Lecteur vidéo (contrôles, progression persistée, prochain épisode, lecture auto) | ✅ |
| **Mes sources Telegram** (liste, ajout avec validation locale, détails, activation/suppression) | ✅ |
| **Synchronisation simulée** (progression animée, statistiques, historique détaillé) | ✅ |
| **Bibliothèque complète** (Favoris, Suivis, Continuer, Récemment ajoutés, Tous — tri + grille/liste) | ✅ |
| **EpisodeGroupingService** (regroupement des qualités : 1 épisode = plusieurs publications) | ✅ |
| API Telegram réelle, backend, moteur Python, téléchargement réel | ⏳ étapes suivantes |

## Parcours de navigation

```
Profil → Mes sources Telegram → Détail d'une source · Ajouter une source · Synchronisation
Bibliothèque → Animé → Épisodes → Qualité → Lecteur
Bibliothèque → Continuer → Lecteur (reprise) · Récemment ajoutés → Qualité
```

## Lancer le projet

```bash
# Prérequis : Flutter 3.47+ (Dart 3.13+), Android SDK, JDK 17

flutter pub get        # dépendances
flutter run            # lancer sur un appareil/émulateur Android
flutter test           # 46 tests (modèles, services, navigation, écrans)
flutter analyze        # analyse statique (0 problème)
flutter build apk --debug   # APK de débogage
```

## Architecture

```
lib/
├── main.dart                     # Point d'entrée (injection des services)
├── app/                          # Racine MaterialApp, thème, routes nommées (9 routes)
├── core/
│   ├── theme/                    # Palette sombre/violet + thème global
│   └── utils/formats.dart        # Formatage (nombres, dates, temps relatif)
├── features/
│   ├── anime/data/               # Modèles, données mockées, dépôt (interface + mock notifiable)
│   ├── home/  search/  details/  episodes/  quality/  player/   # Écrans 1-6
│   ├── library/
│   │   ├── screens/...           # ÉCRAN 9 — bibliothèque (catégories, tri, grille/liste)
│   │   └── services/library_service.dart   # Regroupement logique des catégories
│   ├── telegram/
│   │   ├── data/
│   │   │   ├── models/           # TelegramSource, SourceStatus, SyncStats,
│   │   │   │                     # SyncProgress, SyncHistoryEntry
│   │   │   └── services/
│   │   │       ├── telegram_service.dart          # Contrat (remplaçable par le vrai service)
│   │   │       ├── mock_telegram_service.dart     # Simulation locale (sync animée)
│   │   │       └── episode_grouping_service.dart  # Regroupement publications → épisodes
│   │   └── screens/              # ÉCRAN 7 — sources, ajout, détails ; ÉCRAN 8 — synchronisation
│   ├── downloads/  profile/      # Placeholders + accès aux sources
├── navigation/                   # Coquille principale + barre de navigation basse
└── shared/widgets/               # Composants réutilisables
```

### Points clés de l'étape 3

- **Séparation service/interface** : les écrans dépendent de l'interface `TelegramService` ;
  remplacer `MockTelegramService` par le vrai service (API Telegram + backend) ne touchera
  pas aux écrans. Idem pour `LibraryService` et `EpisodeGroupingService`.
- **Synchronisation simulée** : progression animée (Analyzing publications… → Regroupement
  des doublons… → Analyse terminée), statistiques qui évoluent, historique par jour avec
  résumé détaillé au tap.
- **Regroupement des qualités** : `EpisodeGroupingService` transforme plusieurs publications
  (1080p + 720p + 480p du même épisode) en UN SEUL épisode — logique prête pour le vrai moteur.
- **Modèles prêts pour Telegram** : `TelegramSource` réserve `telegramChannelId` et
  `accessHash` (non utilisés) ; `RawPublication` réserve `messageId` et `messageLink`.
- **Bibliothèque** : 5 catégories, 5 tris, vue grille/liste ; « Continuer » ouvre directement
  le lecteur à la position enregistrée ; « Suivis » montre la progression par saison et le
  badge NOUVEAU.

## Prochaines étapes (à valider une par une)

1. Connexion à l'API Telegram réelle (API_ID / API_HASH, session utilisateur)
2. Analyse réelle des publications des canaux (branchement d'`EpisodeGroupingService`)
3. Backend + remplacement des dépôts mockés par l'API
4. Lecture réelle, téléchargement, notifications
