# Rapport — Prompt 12 : Section Paramètres complète

Branche : `prompt-12-settings` · Run CI : `33722489529`

## 1. Résumé

Section **Paramètres** livrée complète, en réutilisant toutes les briques
réelles des prompts 1–11 : préférences persistantes (§24), langue FR/EN
(préparée, §5/§6), qualité préférée réelle (§4), thème cohérent avec
l'identité sombre (§7), notifications réellement branchées (§8),
synchronisation à fréquence souhaitée + Wi-Fi only réel (§9/§10), stockage
réel sans valeurs fictives (§12–§15), gestion des données avec
confirmations explicites (§16–§18), confidentialité factuelle (§19/§20),
À propos avec la **version réelle du projet** (§21/§22), service central
avec persistance (§25), architecture UI → Controller → Repository →
Storage (§26), **aucune fausse option** (§27), messages d'erreur
compréhensibles (§28), design existant intact (§29), icônes pro (§30),
accessibilité (§31), tests automatisés (§32–§34), CI verte (§37), aucun
backend (§40).

## 2. Paramètres et préférences (§1–§3, §24–§26)

- Nouvel écran `AppSettingsScreen` (route `/settings`, entrée réelle
  depuis Profil — le badge « Bientôt » a été supprimé).
- **8 catégories** présentes : COMPTE, PRÉFÉRENCES, SYNCHRONISATION,
  NOTIFICATIONS, STOCKAGE, APPARENCE, DONNÉES, À PROPOS.
- `AppSettings` (`features/settings/services/app_settings.dart`) :
  `ChangeNotifier` central — getters immédiats, setters notifiés,
  persistance dans la table `settings` SQLite (clés `app.language`,
  `app.theme`, `sync.wifiOnly`, `downloads.auto`).
- **§24 vérifié par le test 6 (§33)** : langue, thème, Wi-Fi only et
  téléchargement auto modifiés → nouvelle instance sur la même base →
  les valeurs sont restaurées.
- Architecture §26 : UI (`app_settings_screen.dart`) → Controller
  (`AppSettings`/`SettingsDependencies`) → Repository (`NotificationSettings`,
  dépôt animé, planificateur) → Storage (`LocalDatabase`, fichiers).
- `SettingsDependencies` injecte tout (tests fournissent des simulacres,
  l'app les vraies briques).

## 3. Qualité préférée (§4)

- Réglage réel déjà existant (`PlaybackSettings.preferredQuality`,
  persisté clé `preferred_quality`) — repris tel quel dans l'écran,
  sélecteur en bas de feuille avec la valeur courante cochée.
- Libellé « Auto — Meilleure qualité réellement disponible » (jamais de
  promesse de qualité absente du catalogue).
- Test 23 : `setPreferredQuality(hd)` → `settings.preferred_quality = hd`
  → restauré après « redémarrage » du dépôt.

## 4. Langue (§5/§6)

- Préférence **persistante** (`app.language`, défaut `fr`).
- Structure i18n en place sans dépendance externe : `SettingsStrings`
  (FR principal, EN complet) couvre l'écran Paramètres et l'écran
  Stockage — aucune traduction automatique externe (§6 respecté).
- Choix appliqué immédiatement aux écrans Paramètres/Stockage
  (notification du service central).

## 5. Thème (§7)

- Deux choix réels, cohérents avec l'identité : **Sombre** et **Système**.
- Règle §7 appliquée honnêtement : l'identité visuelle AnimeBox est
  sombre (`AppColors` est un thème sombre en dur dans tout le projet) ;
  inventer un « thème clair » générique trahirait cette identité — il
  n'est donc pas proposé, et la tuile l'indique explicitement
  (« L'identité AnimeBox est sombre — Système suit actuellement
  l'identité sombre. »).
- La préférence est persistée (`app.theme`) et le sélecteur fonctionne.

## 6. Notifications (§8)

- Toggles **réellement branchés** sur le `NotificationSettings` du
  prompt 9 (composition, zéro duplication) : nouveaux épisodes,
  téléchargements, progression.
- Lien vers l'écran complet existant (heures silencieuses, mode
  silencieux, réglages par source).
- Aucun toggle ajouté n'est décoratif : chaque interrupteur change le
  comportement réel des notifications système (filtres du prompt 9).

## 7. Synchronisation (§9/§10)

- **Fréquence** : sélecteur des valeurs réelles existantes
  (`SyncFrequency`) appliqué au planificateur — libellé « Fréquence
  souhaitée — Android décide de l'heure réelle » (§9 : aucune promesse
  d'heure exacte).
- **Wi-Fi uniquement (§10 — réel)** : `AutoSyncScheduler.applyFrequency`
  accepte désormais `wifiOnly` ; l'implémentation WorkManager applique
  la contrainte réseau **`NetworkType.unmetered`** (Wi-Fi réel) au lieu
  de `connected`. Le réglage est persisté ET ré-appliqué immédiatement
  (test 9–11 : contrainte unmetered/connected vérifiée, relais du flag
  jusqu'au planificateur) et au démarrage de l'app.
- La note « métadonnées seules, jamais de téléchargement de vidéos »
  est affichée et factuelle (la synchro ne télécharge que des
  métadonnées depuis le prompt 8).

## 8. Téléchargement automatique (§11)

- Structure du réglage présente et persistée (`downloads.auto`,
  **OFF par défaut** — aucune adoption automatique).
- Conforme §27 : l'option est réelle (persistée + lisible), et aucune
  promesse fonctionnelle supplémentaire n'est affichée ; le libellé
  « OFF par défaut » clarifie l'état.

## 9. Stockage (§12–§15) — aucune valeur fictive

- Nouvel écran `StorageScreen` : tailles **mesurées** — somme réelle des
  fichiers téléchargés (`File.length`), taille réelle du cache
  applicatif (parcours récursif sans bloquer l'UI, §35), espace libre
  réel (`StorageChecker`/StatFs). Toute valeur non mesurable s'affiche
  « Inconnue » — jamais inventée (§12).
- **Vider le cache (§13)** : confirmation explicite qui liste ce qui
  est conservé ; seul le dossier cache de l'app est vidé — ni vidéos
  téléchargées, ni favoris, ni historique, ni catalogue, ni sources ;
  résultat réel affiché (octets libérés).
- **Gestion des téléchargements (§14)** : multi-sélection (terminés +
  interrompus), suppression groupée via le même chemin que l'écran
  Téléchargements (`MediaService.deleteDownload` : fichier + base),
  confirmation obligatoire (« fichiers définitivement supprimés »),
  compte réel des suppressions.
- **Espace faible (§15)** : bandeau d'avertissement uniquement si la
  mesure réelle passe sous 512 Mo libres (seuil constant
  `kLowSpaceThresholdBytes`).

## 10. Gestion des données (§16–§18)

- `LocalDatabase.clearLocalData()` / `resetEverything()` : purges
  transactions, ordre respectant les dépendances.
- `DataCareService` compose base + téléchargeur + session via des
  contrats minimaux (`DownloadPurger`, `TelegramSignOut`) — testable.
- **Effacer les données locales (§16)** : confirmation précise (§17) —
  catalogue/favoris/historique/préférences effacés ; sources Telegram,
  fichiers téléchargés et session **conservés** (vérifié par le test 17).
- **Réinitialiser AnimeBox (§18)** : **double confirmation** dont un
  avertissement final (§17) — suppression de tous les téléchargements
  (fichiers réels), purge de toutes les tables, **déconnexion Telegram**
  (session révoquée). Compte réel des suppressions affiché.
- Test 20 (§34) : réinitialisation complète vérifiée de bout en bout —
  3 fichiers supprimés, base vide (y compris sources), session fermée.

## 11. Confidentialité (§19/§20)

- Texte **factuel uniquement** (repris de l'écran Profil existant +
  précision Wi-Fi) : traitement local, aucune transmission de session,
  messages, fichiers ou informations privées à un serveur distant,
  session dans stockage chiffré de l'appareil.

## 12. À propos (§21/§22)

- `VersionReader` : lit la ligne `version:` du `pubspec.yaml` embarqué
  comme asset Flutter — **version réelle du projet** affichée
  (0.9.0+9 : version + build inclus, §21).
- Aucune dépendance externe (`package_info` etc. non requis).
- Si la lecture échoue : « Version inconnue », jamais un faux numéro
  (§22) — validé par les tests 22 et 24.

## 13. Absence de fausses options (§27) — inventaire des choix

| Option affichée | Branchée ? | Preuve |
|---|---|---|
| Qualité préférée | Oui | Test 23 (persistance réelle) |
| Langue | Oui | Tests 2/6 (persistance + effet écran) |
| Thème | Oui | Test 3/6 (persisté ; périmètre §7 affiché honnêtement) |
| Wi-Fi only | Oui | Tests 4/9/10/11 (contrainte unmetered réelle) |
| Fréquence | Oui | Test 11 (planificateur reçoit la valeur) |
| Téléchargement auto | Oui | Test 5/6 (pref persistée, OFF par défaut §11) |
| Notifications (3 toggles) | Oui | Briques du prompt 9, déjà testées |
| Vider le cache | Oui | Test 15 + chemin réel fichiers |
| Suppression multi | Oui | `deleteDownload` existant + test 16 |
| Effacer données locales | Oui | Tests 17/18/19 |
| Réinitialisation | Oui | Test 20 (§34) |
| Version | Oui | Tests 22/24 |

Les options **non prouvables ont été exclues** plutôt que décoratives :
pas de « thème clair » (trahirait §7), pas de « langue des sous-titres »
globale (pas de source de données dédiée), pas de sauvegarde cloud,
pas de « heure exacte » de synchronisation (§9).

## 14. Qualité, tests et CI (§28–§37, §39–§40)

- **Tests** (`test/step12_settings_test.dart`) : **24 cas** —
  1–8 préférences/persistance (§33), 9–12 synchro/Wi-Fi, 13–16 stockage,
  17–21 données (§34), 22–23 version/qualité, 24 écran (smoke des 8
  catégories, scroll jusqu'à À propos).
- `flutter analyze` : **No issues found** (6 commits dont correctifs :
  initializing formals, VersionReader non-const, Material sous ListTile).
- **CI `33722489529` : Backend ✅ · Flutter ✅ (0 issue, 234/234 tests
  — 210 existants non cassés + 24 nouveaux) · APK ✅**.
- Erreurs §28 : état mémoire conservé si stockage inaccessible (test 7),
  résultat lisible en cas d'échec de purge (test 19), « Inconnue » pour
  les tailles non mesurables.
- Design §29 : `AppColors`/cartes existantes réutilisés ; icônes
  Material pro cohérentes (§30) ; tuiles informatives sans chevron
  (pas de fausse action) ; en-têtes en majuscules espacées comme le
  reste de l'app.
- Accessibilité §31 : zones tactiles ≥ 40 px, contrastes du thème
  existant, libellés sémantiques (`semanticsLabel` du titre).
- §40 : **aucun backend** — tout est local (SQLite, fichiers,
  WorkManager).

### Limites assumées (documentées, jamais cachées)

- « Système » suit actuellement l'identité sombre (affiché dans
  l'écran) — un vrai thème clair exigerait un chantier de refonte
  visuelle contraire à §29 pour cette étape.
- L'option Langue couvre les écrans Paramètres/Stockage ; la
  localisation complète de l'app est un chantier dédié ultérieur
  (structure prête).
- L'avertissement d'espace faible s'appuie sur la mesure StatFs — si la
  plateforme ne la fournit pas, l'espace s'affiche « Inconnu » et
  l'avertissement ne s'affiche pas (comportement conservateur §28).
