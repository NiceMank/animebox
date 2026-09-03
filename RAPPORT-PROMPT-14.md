# RAPPORT — Prompt 14 : Remplacement complet du système de couleurs (violet → bleu)

Branche : `prompt-14-blue-theme` · Base : `main` @ `3296d98` (prompts 1-13 livrés).

## 1. Ancien système identifié

- **`lib/core/theme/app_colors.dart`** : SEULE source de couleurs du projet (audit : **688** usages
  d'`AppColors` dans `lib/`, **0** `Colors.purple`/`deepPurple` dispersé, aucune autre classe
  `static const Color`). 19 constantes violettes (`primary #8B5CF6`, surfaces noir-violet,
  dégradé magenta `#D946EF`).
- **`lib/core/theme/app_theme.dart`** : `AppTheme.dark` **uniquement** (aucun thème clair).
- **`lib/features/settings/services/app_settings.dart`** : `AppThemeMode {dark, system}` persisté ;
  note i18n « l'identité AnimeBox est sombre — Système suit l'identité sombre » (obsolète).
- Stragglers hors source unique (repris avant bascule) : 3 gradients avec hex violet en dur
  (`anime_details_screen.dart:142`, `episode_list_screen.dart:220`, `hero_card.dart:38` → `0x_ _0A0817`),
  8 commentaires « violet », 1 commentaire « magenta » implicite (dégradés).

## 2. Nouveau système créé / adapté

**Une couleur = un seul endroit (§3/§18).** `app_colors.dart` est réécrit en trois parties :

- `AppColorsDark` — palette sombre immuable : fond noir-bleu `#0A1020`, surfaces bleutées
  `#131B2E/#1A2438/#141D31/#0C1424`, bleu primaire `#3B82F6`, primaire sombre `#1D4ED8`,
  primaire lumineux `#93C5FD`, accent ciel `#38BDF8`, divider `#25354F`, textes
  `#F2F6FD/#A4B0CC/#6B7793`. Dégradés 100 % bleus (le magenta disparaît).
- `AppColorsLight` — vrai mode clair (§6) : fonds blanc/gris très clair `#F7F9FD/#FFFFFF/#F0F4FA`,
  texte sombre `#101828/#475467/#98A2B3`, bleu accent lisible sur blanc `#2563EB/#1D4ED8/#1E40AF`,
  divider `#E2E8F2`.
- `AppColors` — palette ACTIVE (mêmes noms de champs qu'avant) + **`AppColors.apply(Brightness)`** :
  point d'entrée unique qui bascule TOUTES les couleurs d'un coup. Les 688 call-sites sont intacts
  (noms inchangés) et suivent le thème automatiquement.

**Sémantique figée (§4)** dans les deux palettes : succès = vert (`#34D399` / `#059669`),
avertissement = ambre (`#FBBF24` / `#D97706`), erreur = rouge franc (`#EF4444` / `#DC2626`) —
**jamais bleuisés**. VF = rose (`#FB7185`), VOSTFR = ciel (`#38BDF8`) conservés (couleurs de contenu).

**Adaptations structurelles nécessaires** (AppColors est devenu dynamique à chaud) :
- 303 `const` retirés des portées constructeur contenant `AppColors` (scanner dédié, machine à
  états chaînes/commentaires/génériques — retrait sémantiquement nul, seul l'optimisation const change) ;
- `_SettingsTile` / `_confirm` : valeurs par défaut `AppColors.*` rendues nullables et résolues
  au build (`color ?? AppColors.xxx`) — les valeurs par défaut restent vivantes au changement de thème ;
- 3 gradients de fondu des images détail/épisodes/héro désormais calculés depuis
  `AppColors.background.withValues(...)` (fonctionnent en clair ET sombre — non recalculés en image :
  les posters eux-mêmes sont intacts, §10) ;
- `app_theme.dart` : `AppTheme.dark` reparamétré sur la palette sombre bleue, **NOUVEAU `AppTheme.light`**
  réel (même typographie/rayons — aucun redesign, seules les couleurs changent) ; `fontFamily: 'Poppins'`
  rendue explicite dans le `textTheme` (le `copyWith(textTheme:)` ne l'hérite plus, suppression du
  getter `ThemeData.fontFamily` dans Flutter stable — robustesse identique sombre/clair).

## 3. Endroits où le bleu est appliqué (portées §5-§12)

Toutes les portées passent par `AppColors` (source unique) — bleu appliqué automatiquement :
- **Navigation** : item actif de la barre du bas en bleu, fond `bottomBar` du thème ;
- **Boutons** : `PrimaryButton` en dégradé bleu (primaire), variante `outlined` en bordure bleue
  (secondaire), boutons icône/texte sur couleurs de surface ;
- **Progression/lecture** : barres, indicateurs, sliders actifs en bleu lumineux (sombre) / bleu
  lisible (clair) ; sélecteurs qualité/langue avec état sélectionné bleu ;
- **Bibliothèque** : onglet actif, filtres sélectionnés, badge favoris en bleu ;
- **Bibliothèque/Telegram** : **COULEURS SEULEMENT** — aucune logique, API, session, sync ou
  téléchargement n'a été touché (seuls les noms de couleurs résolues ont changé) ;
- **Onboarding (3 écrans)** : compositions inchangées ; accents, indicateurs et bouton « Commencer »
  passent au bleu via la palette (illustrations : seules les couleurs de peinture changent) ;
- **Paramètres** : switches/radios/sliders/sélections actives en bleu, liens en bleu ;
- **Sémantique intacte** : succès vert, avertissement ambre, erreur rouge partout (badges de source,
  indicateurs d'état, confirmations destructrices).

## 4. Vérification Dark Mode (§19)

- `AppColorsDark` : fond sombre (#0A1020, luminance < 3 %), surfaces légèrement bleutées
  (canal bleu dominant — testé), bleu lumineux cantonné aux accents (bouton principal, sélection,
  progression, focus) — **pas de gros aplats bleus** (les surfaces restent quasi neutres).
- Thème par défaut = sombre, inchangé pour les utilisateurs existants (valeurs persistées
  `dark`/`system` lues à l'identique — test de rétrocompatibilité).
- Sélecteur : Sombre/Clair/Système, appliqué **instantanément** (`ListenableBuilder` sur
  `AppSettings` + `AppColors.apply` + `ThemeMode` Material) ; le mode Système suit Android en direct
  (`WidgetsBindingObserver.didChangePlatformBrightness`).

## 5. Vérification Light Mode (§19/§20)

- Vrai thème clair : `AppTheme.light` (fonds lumineux > 90 %, texte `bodyLarge` sombre,
  `colorScheme.primary` bleu) — testé (luminance du scaffold > 0.9, texte < 0.05).
- `AppColors.apply(Brightness.light)` permute TOUTES les couleurs actives (test exhaustif des
  19 champs) puis restauration sombre — aucune fuite d'état.
- Barres système resynchronisées (icônes sombres sur clair, barre de navigation dans `bottomBar`).
- Réglage `light` persisté (`app.theme = 'light'`), survit au redémarrage (test SQLite disque réel).

## 6. Recherche globale violets (§14) — pas de résidu accidentel

- Palette : 0 occurrence `#8B5CF6/#6C3AE8/#B9A4FF/#D946EF/0A0817` dans `lib/` (les seules mentions
  restantes sont les assertions **négatives** du test qui prouvent leur disparition) ;
- `Colors.purple/deepPurple` : 0 occurrence (avant comme après) ;
- 8 commentaires/docs « violet » → reformulés en « bleu » ;
- Couleurs de contenu NON touchées (§14) : posters/images/illustrations de contenu, voiles noirs
  du lecteur vidéo, pastilles VF (rose).

## 7. Contraste & accessibilité (§15)

- Textes : sombre `#F2F6FD`/`#A4B0CC` sur `#0A1020` ; clair `#101828`/`#475467` sur `#F7F9FD`.
- Accent bleu lisible dans les DEUX modes : `#3B82F6`/`#93C5FD` (sombre) vs `#2563EB`/`#1E40AF` (clair).
- Bordures/dividers définis en clair (`#E2E8F2`) comme en sombre (`#25354F`).

## 8. Résultats `flutter analyze` / `flutter test` / build

- **1ᵉʳ run CI (33750149673)** : 6 issues (3× `non_constant_default_value` sur defaults `AppColors`,
  `prefer_const_constructors_in_immutables` lié, 2× `ThemeData.fontFamily` supprimé de Flutter stable)
  → corrigées au commit suivant.
- **Run final (33750876732)** : `flutter analyze --no-pub` = **« No issues found » (17 s)** ;
  `flutter test` = **267/267 tests verts** (247 historiques + **20 nouveaux** `test/step14_theme_test.dart`
  : palettes exactes, sémantique vert/ambre/rouge, hot-swap complet, thèmes sombre/clair,
  persistance 3 modes + rétrocompatibilité, chaînes FR/EN) ;
- **Backend** (pytest + smoke) : vert (non touché) ;
- **Android APK release** : **build OK** (artefact `AnimeBox-APK` publié) — run complet SUCCESS.

## 9. Workflow CI / limites honnêtes

- `.github/workflows/ci.yml` **non modifié** (§20).
- Vérification visuelle téléphone/émulateur : non exécutable depuis le sandbox — couverte par les
  tests de valeurs/thèmes/persistance et par la recompilation APK ; les gradients de fondu ont été
  revus statiquement pour les deux modes.
- Aucun redesign, aucune route ajoutée, aucune fonctionnalité nouvelle : seules les couleurs
  (et leur sélection/persistance) ont changé — identifiant §27 respecté (aucune promesse fictive).
