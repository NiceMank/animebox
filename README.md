# AnimeBox 📺

Application mobile **Android** (Flutter) qui transformera vos canaux Telegram d'animés en une
bibliothèque organisée : détection automatique des titres, saisons, épisodes, qualités et langues.

> **Étape actuelle : 1 — Fondations + 3 premiers écrans** (données mockées, sans Telegram ni backend).

## État de l'étape 1

| Fonctionnalité | État |
| --- | --- |
| Navigation basse persistante (Accueil / Recherche / Bibliothèque / Téléchargements / Profil) | ✅ fonctionnelle |
| Écran Accueil (carousel, 🔥 Nouveaux épisodes, ⭐ Mes animés, ▶ Continuer) | ✅ fonctionnel |
| Écran Recherche (champ + 6 filtres : saison, épisode, qualité, langue, genre, source) | ✅ fonctionnelle |
| Écran Fiche animé (onglets Épisodes / Détails, Favoris / Reprendre / Suivre) | ✅ fonctionnel |
| Favoris & suivi (état local notifiable) | ✅ fonctionnels |
| Données mockées : Solo Leveling, One Piece, Jujutsu Kaisen, Demon Slayer | ✅ |
| Telegram, moteur Python, backend, streaming, téléchargement | ⏳ étapes suivantes |

## Lancer le projet

```bash
# Prérequis : Flutter 3.47+ (Dart 3.13+), Android SDK, JDK 17

flutter pub get        # dépendances
flutter run            # lancer sur un appareil/émulateur Android
flutter test           # 16 tests (modèles, dépôt, navigation, recherche, filtres)
flutter analyze        # analyse statique (0 problème)
flutter build apk --debug   # APK de débogage
```

## Architecture

```
lib/
├── main.dart                     # Point d'entrée (injection du dépôt)
├── app/                          # Racine MaterialApp, thème, routes nommées
├── core/theme/                   # Palette (fond noir/violet, accents lumineux) + thème
├── features/
│   ├── anime/data/
│   │   ├── models/               # Anime, Season, Episode, VideoQuality, SearchFilters, LibraryEntry
│   │   ├── mock/                 # Données de démonstration locales (kMockAnime)
│   │   └── repositories/         # Interface AnimeRepository + implémentation mockée
│   ├── home/                     # Accueil (+ widgets héros, cartes)
│   ├── search/                   # Recherche + feuille de filtres
│   ├── details/                  # Fiche animé (onglets Épisodes / Détails)
│   ├── library/                  # Bibliothèque (favoris, suivis)
│   ├── downloads/                # Placeholder Téléchargements
│   └── profile/                  # Placeholder Profil (Telegram à venir)
├── navigation/                   # Coquille principale + barre de navigation basse
└── shared/widgets/               # Composants réutilisables (AnimeCard, EpisodeCard,
                                  # AppSearchBar, QualityBadge, SectionTitle, boutons…)
```

### Points clés

- **Séparation données / interface** : les écrans ne connaissent que l'interface `AnimeRepository`.
  Remplacer le mock par une API backend (étape suivante) ne touchera pas aux écrans.
- **Données notifiables** : le dépôt est un `Listenable` — les bascules favori/suivi rafraîchissent
  l'interface instantanément (accueil, bibliothèque, fiche).
- **Recherche locale** : insensible à la casse et aux accents, combinable aux 6 filtres.
- **Navigation** : `IndexedStack` (l'état de chaque onglet est conservé) + routes nommées
  (`/anime/details` avec l'id en argument) pour les fiches.
- **Design** : thème sombre global, Poppins embarquée (aucune dépendance réseau), composants
  réutilisables, animations discrètes, mise en page responsive (grilles, `Wrap`, textes flexibles).

## Prochaines étapes (à valider une par une)

1. Connexion Telegram + ajout de canaux comme sources
2. Moteur de détection (titre, saison, épisode, qualité, langue, sous-titres)
3. API backend + remplacement du dépôt mocké
4. Lecture, téléchargement, notifications, synchronisation
