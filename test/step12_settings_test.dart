// Prompt 12 — Paramètres complets : préférences persistantes, stockage
// réel, gestion des données, réinitialisation, version réelle, Wi-Fi
// only réel (unmetered). Aucune valeur fictive (§27).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';

import 'package:animebox/features/anime/data/repositories/local_anime_repository.dart';
import 'package:animebox/features/anime/data/models/video_quality.dart';
import 'package:animebox/features/local/data/local_database.dart';
import 'package:animebox/features/notifications/services/notification_settings.dart';
import 'package:animebox/features/settings/screens/app_settings_screen.dart';
import 'package:animebox/features/settings/services/app_settings.dart';
import 'package:animebox/features/settings/services/data_care_service.dart';
import 'package:animebox/features/settings/services/settings_dependencies.dart';
import 'package:animebox/features/settings/services/storage_service.dart';
import 'package:animebox/features/settings/services/version_reader.dart';
import 'package:animebox/features/sync/models/sync_frequency.dart';
import 'package:animebox/features/sync/services/in_memory_auto_sync.dart';
import 'package:animebox/features/sync/services/workmanager_auto_sync.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';
import 'package:animebox/features/telegram/data/services/mock_telegram_service.dart';
import 'package:animebox/core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Simulacres de test (contrats minimaux des services).
// ---------------------------------------------------------------------------

class _FakeDownloadPurger implements DownloadPurger {
  final List<String> ids = <String>['v1', 'v2', 'v3'];
  final List<String> deleted = <String>[];

  @override
  Future<void> delete(String versionId) async => deleted.add(versionId);

  @override
  List<String> downloadVersionIds() => List<String>.of(ids);

  @override
  List<String?> downloadFilePaths() => <String?>['/x/v1.mp4', '/x/v2.mp4', null];
}

class _FakeSignOut implements TelegramSignOut {
  bool called = false;

  @override
  Future<void> disconnect() async => called = true;
}

Future<LocalDatabase> _seededDatabase() async {
  final LocalDatabase db = (await LocalDatabase.openInMemory())!;
  await db.upsertSource(<String, Object?>{'id': 's1', 'name': 'Canal A', 'username': 'canal_a'});
  await db.upsertAnime(<String, Object?>{
    'id': 'a1',
    'title': 'Anime A',
    'created_at': DateTime(2024).toIso8601String(),
  });
  await db.setFavorite('a1', true);
  await db.saveProgress('a1', 'e1', const Duration(minutes: 3).inMilliseconds,
      durationMs: const Duration(minutes: 24).inMilliseconds);
  await db.upsertDownload(<String, Object?>{
    'id': 'dl-1',
    'version_id': 'v1',
    'anime_id': 'a1',
    'season_id': 'se1',
    'episode_id': 'e1',
    'status': 'completed',
    'created_at': DateTime(2024).toIso8601String(),
    'updated_at': DateTime(2024).toIso8601String(),
  });
  await db.setSetting('preferred_quality', 'hd');
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Service central des préférences (§25/§26)', () {
    test('1. valeurs par défaut réelles (FR, sombre, Wi-Fi libre, auto OFF)', () async {
      final AppSettings settings = AppSettings();
      await settings.ensureLoaded();
      expect(settings.language, 'fr');
      expect(settings.theme, AppThemeMode.dark);
      expect(settings.syncWifiOnly, isFalse);
      expect(settings.autoDownload, isFalse, reason: '§11 : OFF par défaut');
    });

    test('2. setLanguage modifie, notifie et persiste', () async {
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final AppSettings settings = AppSettings(database: db);
      await settings.ensureLoaded();
      int notified = 0;
      settings.addListener(() => notified++);
      await settings.setLanguage('en');
      expect(settings.language, 'en');
      expect(notified, greaterThan(0));
      expect(await db.getSetting('app.language'), 'en');
    });

    test('3. setTheme persiste (système)', () async {
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final AppSettings settings = AppSettings(database: db);
      await settings.ensureLoaded();
      await settings.setTheme(AppThemeMode.system);
      expect(settings.theme, AppThemeMode.system);
      expect(await db.getSetting('app.theme'), 'system');
    });

    test('4. setSyncWifiOnly persiste', () async {
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final AppSettings settings = AppSettings(database: db);
      await settings.ensureLoaded();
      await settings.setSyncWifiOnly(true);
      expect(settings.syncWifiOnly, isTrue);
      expect(await db.getSetting('sync.wifiOnly'), 'true');
    });

    test('5. setAutoDownload persiste', () async {
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final AppSettings settings = AppSettings(database: db);
      await settings.ensureLoaded();
      await settings.setAutoDownload(true);
      expect(await db.getSetting('downloads.auto'), 'true');
    });

    test('6. §33 : les préférences survivent à un redémarrage', () async {
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final AppSettings first = AppSettings(database: db);
      await first.ensureLoaded();
      await first.setLanguage('en');
      await first.setTheme(AppThemeMode.system);
      await first.setSyncWifiOnly(true);
      await first.setAutoDownload(true);

      // Nouvelle instance sur la MÊME base = redémarrage de l'app.
      final AppSettings second = AppSettings(database: db);
      await second.ensureLoaded();
      expect(second.language, 'en');
      expect(second.theme, AppThemeMode.system);
      expect(second.syncWifiOnly, isTrue);
      expect(second.autoDownload, isTrue);
    });

    test('7. absence de base : état mémoire fonctionnel (§28)', () async {
      final AppSettings settings = AppSettings(database: null);
      await settings.ensureLoaded();
      expect(settings.loaded, isTrue);
      await settings.setLanguage('en');
      expect(settings.language, 'en');
    });

    test('8. chaînes FR principales / EN prêtes (§5)', () {
      const SettingsStrings fr = SettingsStrings('fr');
      const SettingsStrings en = SettingsStrings('en');
      expect(fr.title, 'Paramètres');
      expect(fr.sectionStorage, 'STOCKAGE');
      expect(en.title, 'Settings');
      expect(en.sectionStorage, 'STORAGE');
      expect(fr.eraseLocalDataConfirm, contains('données locales'));
    });
  });

  group('2. Synchronisation — Wi-Fi only réel (§10)', () {
    test('9. constraintsFor : unmetered si Wi-Fi only, connected sinon', () {
      expect(WorkmanagerAutoSyncScheduler.constraintsFor(wifiOnly: true).networkType,
          NetworkType.unmetered);
      expect(WorkmanagerAutoSyncScheduler.constraintsFor().networkType, NetworkType.connected);
    });

    test('10. le planificateur reçoit la contrainte Wi-Fi', () async {
      final InMemoryAutoSyncScheduler scheduler = InMemoryAutoSyncScheduler();
      await scheduler.applyFrequency(SyncFrequency.hourly, wifiOnly: true);
      expect(scheduler.applied, SyncFrequency.hourly);
      expect(scheduler.appliedWifiOnly, isTrue);
      await scheduler.applyFrequency(SyncFrequency.daily);
      expect(scheduler.appliedWifiOnly, isFalse);
    });

    test('11. setSyncFrequency relaie fréquence + Wi-Fi only et persiste', () async {
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final InMemoryAutoSyncScheduler scheduler = InMemoryAutoSyncScheduler();
      final NotificationSettings settings = NotificationSettings(database: db);
      settings.attachScheduler(scheduler);
      await settings.load();
      await settings.setSyncFrequency(SyncFrequency.every3Hours, wifiOnly: true);
      expect(scheduler.applied, SyncFrequency.every3Hours);
      expect(scheduler.appliedWifiOnly, isTrue);
      expect(settings.syncFrequency, SyncFrequency.every3Hours);
    });

    test('12. fréquence présentée comme SOUHAITÉE (§9, jamais garantie)', () {
      const SettingsStrings s = SettingsStrings('fr');
      expect(s.syncFrequencyNote.toLowerCase(), contains('souhaitée'));
      expect(s.syncWifiOnlyNote.toLowerCase(), contains('métadonnées'));
    });
  });

  group('3. Stockage réel (§12/§13/§14/§15)', () {
    test('13. formatBytes lisible', () {
      expect(formatBytes(1073741824), '1.0 Go');
      expect(formatBytes(5242880), '5.0 Mo');
      expect(formatBytes(2048), '2.0 Ko');
      expect(formatBytes(500), '500 o');
    });

    test('14. snapshot : valeurs inconnues quand non mesurables, jamais fictives', () async {
      final FakeStorageService service = FakeStorageService();
      final StorageSnapshot snap = await service.snapshot();
      expect(snap.downloadsBytes, isNull);
      expect(snap.cacheBytes, isNull);
      expect(snap.freeBytes, isNull);
    });

    test('15. clearCache retourne les octets réellement libérés', () async {
      final FakeStorageService service = FakeStorageService()..freedOnClear = 4096;
      expect(await service.clearCache(), 4096);
      expect(service.clearCalls, 1);
    });

    test('16. deleteFile enregistre le chemin du téléchargement supprimé (§14)', () async {
      final FakeStorageService service = FakeStorageService();
      await service.deleteFile('/dl/a.mp4');
      await service.deleteFile(null);
      expect(service.deletedPaths, <String?>['/dl/a.mp4', null]);
    });
  });

  group('4. Gestion des données (§16/§17/§18)', () {
    test('17. clearLocalData vide données personnelles, CONSERVE sources/téléchargements', () async {
      final LocalDatabase db = await _seededDatabase();
      await db.clearLocalData();
      expect(await db.countAnime(), 0, reason: 'catalogue effacé');
      expect(await db.loadFavorites(), isEmpty, reason: 'favoris effacés');
      expect(await db.loadProgress(), isEmpty, reason: 'historique effacé');
      expect(await db.getSetting('preferred_quality'), isNull, reason: 'préférences effacées');
      expect(await db.listSources(), isNotEmpty, reason: 'sources Telegram conservées (§16)');
      expect(await db.listDownloads(), isNotEmpty, reason: 'téléchargements conservés (§16)');
    });

    test('18. eraseLocalData via le service : succès réel', () async {
      final LocalDatabase db = await _seededDatabase();
      final DataCareService service = DataCareService(database: db);
      final DataCareResult result = await service.eraseLocalData();
      expect(result.success, isTrue);
      expect(await db.countAnime(), 0);
    });

    test('19. eraseLocalData sans base : échec lisible, pas de crash (§28)', () async {
      final DataCareService service = DataCareService(database: null);
      final DataCareResult result = await service.eraseLocalData();
      expect(result.success, isFalse);
      expect(result.error, isNotNull);
    });

    test('20. §34 : réinitialisation complète — TOUT + fichiers + session Telegram', () async {
      final LocalDatabase db = await _seededDatabase();
      final _FakeDownloadPurger purger = _FakeDownloadPurger();
      final _FakeSignOut signOut = _FakeSignOut();
      final DataCareService service =
          DataCareService(database: db, downloads: purger, telegram: signOut);

      final DataCareResult result = await service.resetEverything();

      expect(result.success, isTrue);
      expect(result.downloadsRemoved, 3, reason: 'chaque téléchargement supprimé réellement');
      expect(purger.deleted, <String>['v1', 'v2', 'v3']);
      expect(result.signedOut, isTrue, reason: 'session Telegram déconnectée (§18)');
      expect(signOut.called, isTrue);
      expect(await db.countAnime(), 0);
      expect(await db.listSources(), isEmpty, reason: 'sources effacées à la réinitialisation');
      expect(await db.listDownloads(), isEmpty);
      expect(await db.getSetting('preferred_quality'), isNull);
      expect(await db.loadFavorites(), isEmpty);
    });

    test('21. textes de confirmation explicites (§17) — avertissement final présent', () {
      const SettingsStrings s = SettingsStrings('fr');
      expect(s.resetAppConfirm.toLowerCase(), contains('irréversible'));
      expect(s.resetAppFinal.toLowerCase(), contains('dernier avertissement'));
      expect(s.eraseLocalDataNote.toLowerCase(), contains('destructive'));
    });
  });

  group('5. Version réelle (§21/§22)', () {
    test('22. parseVersion extrait la version RÉELLE du pubspec', () {
      expect(VersionReader.parseVersion('name: animebox\nversion: 1.4.2+7\n\ndependencies:'),
          '1.4.2+7');
      expect(VersionReader.parseVersion('version: 0.9.0+9'), '0.9.0+9');
      expect(VersionReader.parseVersion('name: animebox'), isNull,
          reason: 'aucune valeur inventée si la version est absente');
    });

    test('23. qualité préférée persistée via le dépôt (§4/§24)', () async {
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final LocalAnimeRepository repo = LocalAnimeRepository(database: db);
      await repo.reloadFromDatabase();
      repo.setPreferredQuality(QualityPreference.hd);
      expect(await db.getSetting('preferred_quality'), 'hd');

      // Redémarrage : la préférence est restaurée (§24).
      final LocalAnimeRepository after = LocalAnimeRepository(database: db);
      await after.reloadFromDatabase();
      expect(after.playbackSettings.preferredQuality, QualityPreference.hd);
    });
  });

  group('6. Écran Paramètres (§27 : options réelles uniquement)', () {
    testWidgets('24. les 8 catégories s\'affichent, état réel visible', (WidgetTester tester) async {
      final SettingsDependencies deps = SettingsDependencies(
        appSettings: AppSettings(),
        notificationSettings: NotificationSettings(),
        repository: MockAnimeRepository(),
        telegramService: MockTelegramService(),
      );
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: AppSettingsScreen(dependencies: deps),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Paramètres'), findsOneWidget);
      expect(find.text('COMPTE'), findsOneWidget);
      expect(find.text('PRÉFÉRENCES'), findsOneWidget);
      expect(find.textContaining('animebox_demo'), findsOneWidget,
          reason: 'état Telegram réel (compte simulé connecté)');
      expect(find.text('Qualité préférée'), findsOneWidget);

      // Les sections basses existent dans l'arborescence (scroll jusqu'à elles).
      await tester.scrollUntilVisible(find.text('À propos d\'AnimeBox'), 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('À PROPOS'), findsOneWidget);
      expect(find.text('Version inconnue'), findsOneWidget,
          reason: '§22 : jamais une version fictive');
    });
  });
}
