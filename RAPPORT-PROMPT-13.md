# Rapport — Prompt 13 : Onboarding AnimeBox

Branche : `prompt-13-onboarding` · Run CI : `33733609591`

## 1. Fichiers créés

| Fichier | Rôle |
|---|---|
| `lib/features/onboarding/models/onboarding_page_data.dart` | Contenu des **exactement 3 écrans** (titres officiels §1, descriptions réelles, 4 points de confidentialité factuels) — aucune donnée fictive |
| `lib/features/onboarding/onboarding_screen.dart` | PageView des 3 pages, boutons Suivant/Suivant/Commencer + « Passer », indicateur, transitions, apparition douce, pulse discret — UI pure (aucune logique de persistance, §7) |
| `lib/features/onboarding/widgets/onboarding_illustrations.dart` | Illustrations cohérentes avec l'app : affiches réelles du catalogue + cube AnimeBox vectoriel (painter), badges qualité existants, TelegramLogo + anneau bouclier — **aucun emoji, aucune icône générique** |
| `test/step13_onboarding_test.dart` | 13 tests (contenu, navigation, persistance, intégration, responsive) |
| `test/onboarding_helper.dart` | Helper `completedOnboardingSettings()` pour les tests historiques |

## 2. Fichiers modifiés

| Fichier | Changement |
|---|---|
| `lib/features/settings/services/app_settings.dart` | Clé `app.onboardingCompleted` + getter + `completeOnboarding()` (service central existant — **aucun second stockage**, §7) |
| `lib/app/animebox_app.dart` | Racine conditionnelle : onboarding au premier lancement uniquement, sinon `HomeShell` ; `_finishOnboarding` (validation + redirection vers le VRAI flow Telegram existant, sauf si compte déjà configuré — §5) ; splash minimal pendant le chargement des préférences |
| `test/step3_test.dart`, `test/step4_widget_test.dart`, `test/widget_test.dart` | Injection d'un `AppSettings` complété (accueil direct attendu par ces tests historiques) — aucune autre modification |

## 3. Fonctionnalités ajoutées

- **3 écrans exacts** : « Bienvenue sur AnimeBox », « Tous vos animés au
  même endroit », « Sécurisé & 100 % privé » (avec les 4 points factuels :
  compte Telegram et sources appartiennent à l'utilisateur, données
  locales, aucun serveur central).
- **Navigation** : Suivant (pages 1–2), **Commencer** (page 3), Passer
  (haut-droite, chaque page), indicateur de progression `CarouselIndicator`
  (composant existant, points animés).
- **Animations légères** (§2) : transitions natives du PageView
  (BouncingScrollPhysics), fade + glissement de 26 ms à l'arrivée de page,
  respiration discrète (2,4 s) du cube/bouclier — rien d'excessif.
- **Design intégré** (§3) : `AppColors`, Poppins, `PrimaryButton`,
  rayons existants, badges qualité existants ; pas de glassmorphism, pas
  de composant Material générique, pas de gradients excessifs.

## 4. Méthode de sauvegarde de l'état (§4)

- Préférence `app.onboardingCompleted` persistée dans la table `settings`
  SQLite via le service central existant `AppSettings` ( même mécanisme
  que langue/thème du prompt 12).
- `completeOnboarding()` appelé par « Commencer » ET « Passer » ;
  l'écran racine attend `ensureLoaded()` avant de décider → l'onboarding
  n'apparaît qu'au **premier lancement** et jamais ensuite.
- **§5** : « Commencer » valide puis pousse la route existante
  `/telegram/connect` (réutilisation du flow réel) **uniquement si aucun
  compte n'est configuré** ; avec un compte existant, l'utilisateur arrive
  directement à l'accueil — aucune reconnexion forcée.

## 5. Tests effectués

`test/step13_onboarding_test.dart` — **13 tests** :

1-3. Contenu officiel exact + préférence persistée + **survie au redémarrage**.
4-7. Affichage initial (titre, indicateur 3 points, Suivant, Passer) ;
navigation 1→2→3 avec bascule Suivant→Commencer ; callbacks Commencer/Passer ;
**petit écran 360×640 sans overflow** (§6/§14).
8-11. Intégration : premier lancement, Commencer → état validé + flow
Telegram réel poussé (aucun compte), compte existant → pas de reconnexion
forcée (accueil direct), Passer → validation sans imposer Telegram.
12. **Persistance disque réelle** : fichier temporaire → validation →
fermeture → réouverture → préférence relue (`test()` simple — la boucle
async réelle est requise pour SQLite).
13. État restauré « terminé » → l'app saute l'onboarding.

Corrections apportées pendant les itérations CI :
- `pumpAndSettle` inutilisable à l'écran (animation infinie du pulse §2)
  → frames explicites tant que l'onboarding est visible.
- Base `:memory:` partagée par l'isolate de test (cache sqflite par chemin)
  → tests d'intégration rendus déterministes (préférences injectées),
  persistance SQL prouvée séparément.
- Vérification §8 : routes OK, 3 pages accessibles, Commencer/Passer
  réels, état sauvegardé, redémarrage sans onboarding (tests 8-13),
  comportements sans/avec compte Telegram (tests 9/10), petits écrans OK
  (test 7), aucun emoji/icône générique introduit.

## 6. Résultats flutter analyze / flutter test / build

- `flutter analyze` → **« No issues found »** (CI run 33733609591).
- `flutter test` → **247/247 tests réussis** (234 historiques intacts + 13
  nouveaux ; les 241+6 vérifications passent toutes).
- **Build final (§10)** : job `Android — build APK (artefact de test)` ✅
  sur GitHub Actions (workflow existant inchangé — aucune configuration de
  projet modifiée) ; Backend ✅ également.
- Fonctionnalités existantes : aucune cassée (les 234 tests historiques
  passent sans adaptation fonctionnelle, uniquement l'injection de
  préférence déjà fournie).

## 7. Limites assumées

- Les illustrations sont des compositions des **assets existants** +
  dessins vectoriels (cube, anneau) — fidèles à la hiérarchie des
  maquettes (affiches duo, cube central, sources/Telegram) sans dépendre
  d'illustrations externes.
- « Passer » valide l'onboarding (choix maquette §3) sans imposer le
  parcours Telegram — distinction documentée avec « Commencer » (§5).
