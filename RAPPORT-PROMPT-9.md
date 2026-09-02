# Rapport final — Prompt 9 : Notifications et synchronisation

Branche : `prompt-9-notifications` (commits `f5fd06d`…`fc73181`)
Version : `0.9.0+9`
Validation : pipeline GitHub Actions complet au vert (analyse 0 issue, 174 tests passés, APK Android construit — artefact 77,4 Mo).

---

## 1. Architecture générale

- **100 % locale** : aucun backend, aucun serveur Vercel, aucun Python. Les notifications s'affichent exclusivement via le package **`flutter_local_notifications` 17** et les données ne quittent jamais l'appareil sauf par le client Telegram réel (TDLib) déjà en place.
- **Trois familles de notifications**, un canal Android dédié chacune (créés à l'initialisation) :
  - **Nouveaux épisodes** — importance haute, priorité par défaut.
  - **Téléchargements** — importance moyenne.
  - **Synchronisation** — importance basse (jamais intrusive).
- **Réseau d'objets testable** : `NotificationService` (abstrait) ⇐ `LocalNotificationService` (réel, greffon) et `InMemoryNotificationService` (tests) ; un `NotificationCenter` centralise tout le métier (déduplication, groupement, réglages vers canaux) ; `AutoSyncScheduler` (abstrait) ⇐ `WorkmanagerAutoSyncScheduler` (réel) / `InMemoryAutoSyncScheduler` (tests).

## 2. Ce qui est 100 % local

- Source de vérité des catalogue/bibliothèque/progression/téléchargements : SQLite (`LocalDatabase`, schéma v3).
- Registre des notifications d'épisodes : table `notifications_sent` (clefs `anime_id/season_id/episode_id/versions`) — alimentée uniquement par des entrées réellement notifiées.
- Préférences par animé (`anime_preferences`) et état de synchronisation (`meta`, tables `sync_history` déjà présentes).
- Toutes les conventions nommées dans le code : « 100 % local — jamais de sortie réseau ».

## 3. Notifications « nouveaux épisodes » — point par point

- **Détection** : sur chaque synchronisation réussie (`service.onSyncCompleted = center.handleSyncSummary`), le centre compare les épisodes connus aux nouvelles versions produites par le sync pour `anime/season/episode/versions` distincts.
- **Dédoublonnage irréversible** **(i)** : un épisode déjà notifié ne produit jamais une seconde notification — garde par base de données et non par la mémoire vive.
- **Groupement qualité** **(ii)** : un épisode disponible en 1080p, 720p et 480p produit une seule notification : corps « 3 qualités disponibles » (202=2 — formatage exact).
- **Ouverture correcte** **(iii)** : `tap` → navigation Anime → Saison → Épisode (itératif : `AppRoutes.router` avec `NotificationPayload(animeId, seasonNumber, episodeNumber)`) — jamais l'écran d'accueil.
- **Canal / badge / désactivation** : canal dédié, `badge` Android géré par le système, interrupteur global « Notifications épisodes » qui désactive entièrement la famille.
- **Coupures maîtresses** : interrupteur par source (ON/OFF), interrupteur par animé, **mode silencieux + heures calmes** — tout est consulté *avant* l'envoi ; en heures calmes les épisodes restent enregistrés localement sans notification, puis les notifications reprennent normalement.

## 4. Notifications de téléchargement — événements réels uniquement

- **Progression** **(i)** : uniquement quand le `DownloadManager` reçoit des événements `progress` réels (ratio %) depuis la passerelle TDLib — mise à jour de la progression affichée (throttle système : max 1 màj/2 s par téléchargement).
- **Terminé** **(iii)** : envoi sur événement `completed` réel — ouverture du fichier local organisé.
- **Échoué** **(ii)** : sur événement `failed` réel — action de notification **« Reprendre »** restaurée au `DownloadManager`.
- **((contre-exemples couverts))** : jamais de barre de progression simulée ; jamais de « terminé » sans fichier sur disque (tests step 8 + step 9 le vérifient).
- 3 tests notification + 6 tests téléchargement en widget/unitaire avec `InMemoryNotificationService` interposé.

## 5. Notifications de synchronisation — messages précis

- **Succès** : « Synchronisation terminée : 3 sources, 47 messages analysés, 12 épisodes mis à jour » — valeurs entièrement issues du `SyncSummary` réel.
- **Échec** : le message contient la raison réelle et le nom de chaque source en cause.
- **Fréquence** : une seule notification de synchronisation par événement de fin (optionnelle), sur le canal bas « Synchronisation ».

## 6. Synchronisation automatique — WorkManager, par le système

- **Mécanisme officiel Android** : `workmanager` **0.10.9** (compatible Flutter 3.47 — la 0.5.2 échouait à la compilation Kotlin) ; contrainte `networkType connected`, politique `ExistingPeriodicWorkPolicy.replace`, backoff linéaire 10 min.
 - Intervalle minimal 15 minutes (contrainte système, respectée ; écart système volontairement différable).
 - Léger et incrémentiel : le point d'entrée `@pragma('vm:entry-point')` relit l'état local et ne retélécharge que les deltas via la passerelle.
 - Cancellable (`cancelByUniqueName`) et survivant au redémarrage.
 - **Aucun service permanent, aucune boucle.**
- **Fréquences proposées** **(règle 11)** : Désactivée / 15 min / 30 min / 1h / 3h / 1 jour — présentées comme fréquence *souhaitée* (« fréquence souhaitée, pas garantie ») ; le texte « Le système décide réellement » est explicite.
- **« Synchroniser maintenant »** **(10)** : toujours disponible depuis les paramètres avec résumé complet (sources, messages analysés, épisodes, qualités, erreurs) ; l'état affiché est « il y a 12 minutes » / « en cours » / « échouée » (persistance `meta`).

## 7. Paramètres (par source, par animé, globaux)

- **Écran Notifications** (nouveau, icônes pro, sans émoji) :
  - Interrupteur global par famille (épisodes / téléchargements / synchronisation).
  - **Mode silencieux** + **heures calmes** (23:00→07:00) avec sélecteurs d'heure en heure locale.
  - **Synchronisation automatique** : fréquence, statut, « Synchroniser maintenant ».
  - **Par source** **(18/19/20/21)** : chaque ligne source affiche Sync ON/OFF, Notifications ON/OFF, Téléchargement auto **OFF par défaut**, qualité préférée — **héritée de la qualité globale** sauf si explicitement modifiée.
  - **Par animé** : interrupteur notifications par animé (table `anime_preferences`).
- Paramètres persistés via `LocalDatabase` (colonne `sources.notifications_enabled`, etc.) — migration v3 idempotente.

## 8. Cas de bord — couverts, aucun inventé

- **(22) Connexion perdue** : catalogue local conservé, message « Connexion Internet indisponible » au moment opportun.
- **(23) Source devenue inaccessible** : canal Telegram d'abonnement arrêté proprement, notification informative.
- **(24) Épisode disparu** : la notification n'est pas modifiée, l'épisode est retiré de la liste (pas de nettoyage artificiel).
- **(25) Tâche interrompue** : WorkManager relance au prochain créneau réseau compatible — sans boucle.
- **(26) Jamais de service permanent ni de wakelock.**
- **(27) Session Telegram expirée** : message « Votre session Telegram est expirée [ Reconnecter Telegram ] ».
- **(28) Permission refusée** : fenêtre jalonnée « [ Activer les notifications ] [ Plus tard ] » — l'app **palier par palier**, l'affichage des notifications vient du DEMANDE d'activer la fonction correspondante, **jamais au premier lancement**.

## 9. Aucun contournement, aucun chiffre inventé

- Pas de service Polling, pas de `dart:io` arrière-plan maison, pas de boots-invisibles.
- Notifications « téléchargement » branchées directement sur les événements `progress/completed/failed` du `DownloadManager` (tests factices exclus des deux côtés).

## 10. Commandes à exécuter localement (transparence)

```bash
flutter analyze    # 0 issue (CI : ok)
flutter test       # 174 tests passés (CI : ok)
flutter build apk  # OK — artefact GitHub Actions « AnimeBox-APK » (77,4 Mo)
```

Validation faite dans **GitHub Actions** (à la demande de l'utilisateur — la consigne « ne pas créer d'Actions maintenant » a été explicitement révisée) : `Backend — pytest + smoke test`, `Flutter — analyse + tests`, `Android — build APK (artefact de test)`.

## 11. Corrections intégrées au passage (important — des bugs préexistants)

Ces bugs étaient **déjà sur `main`** et n'avaient jamais été détectés car la CI de `main` échouait *avant* l'exécution des tests (2 issues d'analyse). En mettant l'analyse au vert, 7 tests historiquement cassés sont apparus. Corrigés dans le fil de ce prompt :

1. **SQL invalide** : `status TEXT NOT NULL;` (point-virgule au milieu d'un CREATE TABLE) dans `local_database.dart` (échouait tout l'init de la base sur les nouvelles installations).
2. **Colonnes manquantes** : `downloads.message_link` et `downloads.channel_username` absentes du schéma de création fraîche (v2/v3) alors que `_persist` et `_taskFromRow` les utilisent → la persistance des téléchargements échouait silencieusement. Ajoutées à la création + migration v3 `_addColumnIfExists`.
3. **Compteurs de progression obsolètes** : `DownloadManager` ne mettait à jour `downloadedBytes` que quand une notification/persistance était due (400 ms/2,5 s) → la progression lue entre deux battements restait à 0. Les compteurs sont désormais à jour en mémoire à chaque événement (seules notification/persistance restent bridées).
4. **`recordProgress` silencieux** : retournait sans rien enregistrer hors bibliothèque ; désormais la progression est toujours enregistrée (l'entrée bibliothèque reste facultative) et l'écriture SQLite asynchrone est à l'épreuve d'une base fermée.
5. **`preparePlayback` laissait fuiter `GatewayError`** (fichier supprimé/cache perdu) → désormais plan de repli Telegram avec le vrai message.
6. **Débordement UI 2 px** : rangée « langue » de l'écran qualité (texte + puce sous-titres) — corrigé par `Expanded` + ellipsis.
7. **Fixture de test** : `FakeTelegramGateway.getMessage` honorait pas `failOnNextFetch` (contrairement à `getMessages`).
8. **`workmanager` 0.5.2** → **0.10.9** : la 0.5.2 ne compilait plus avec Flutter 3.47 (`messenger`, `addViewDestroyListener`, `PluginRegistrantCallback` non résolus).

## 12. Critères de succès — statut final

| Critère | Statut |
|---|---|
| 174 tests au vert (`flutter test`) | ✅ CI |
| Analyse propre (`flutter analyze`, 0 issue) | ✅ CI |
| APK Android construit | ✅ CI (77,4 Mo) |
| Notifications et réglages sauvegardés 100 % localement | ✅ |
| Aucune invention, aucune donnée fictive | ✅ tests dédiés |
