import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/local/data/local_database.dart';
import 'package:animebox/features/media/models/download_models.dart';
import 'package:animebox/features/notifications/models/notification_models.dart';
import 'package:animebox/features/notifications/services/in_memory_notification_service.dart';
import 'package:animebox/features/notifications/services/notification_center.dart';
import 'package:animebox/features/notifications/services/notification_service.dart';
import 'package:animebox/features/notifications/services/notification_settings.dart';
import 'package:animebox/features/sync/models/sync_frequency.dart';
import 'package:animebox/features/sync/services/in_memory_auto_sync.dart';
import 'package:animebox/features/telegram/data/gateway/telegram_gateway.dart';
import 'package:animebox/features/telegram/data/models/api_exception.dart';
import 'package:animebox/features/telegram/data/services/local_telegram_service.dart';
import 'package:animebox/features/telegram/data/services/telegram_session_manager.dart';

import 'step7_fake_gateway.dart';

const int _chatA = -1001234567890;
const int _chatB = -1001234567899;

GatewayChat get _channelA => const GatewayChat(
      id: _chatA,
      title: 'Anime VF',
      username: 'anime_vf',
      kind: GatewayChatKind.channel,
    );

GatewayChat get _channelB => const GatewayChat(
      id: _chatB,
      title: 'Anime VOSTFR',
      username: 'anime_vostfr',
      kind: GatewayChatKind.channel,
    );

GatewayMessage _video(int id, int chatId, {String? fileName, String? caption}) => GatewayMessage(
      messageId: id,
      chatId: chatId,
      date: DateTime(2026, 9, 1, 10, id % 60),
      text: caption,
      mediaType: 'video',
      fileName: fileName,
      fileSize: 1400000000,
      mimeType: 'video/x-matroska',
      width: 1920,
      height: 1080,
      messageLink: telegramMessageLink(chatId: chatId, messageId: id, username: 'anime_vf'),
    );

DownloadTask _task(DownloadStatus status,
        {int downloaded = 500, int? expected = 1000, String? error, bool resumable = true}) =>
    DownloadTask(
      id: 'dl-v1',
      versionId: 'v1',
      animeId: 'solo-leveling',
      seasonId: 'solo-leveling-s2',
      episodeId: 'solo-leveling-s2-e8',
      animeTitle: 'Solo Leveling',
      seasonNumber: 2,
      episodeNumber: 8,
      status: status,
      createdAt: DateTime(2026, 9, 1, 10),
      updatedAt: DateTime(2026, 9, 1, 11),
      qualityLabel: '1080p',
      expectedSize: expected,
      downloadedBytes: downloaded,
      error: error,
      resumable: resumable,
    );

Future<void> settle([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late LocalDatabase db;
  late FakeTelegramGateway gateway;
  late LocalTelegramService service;
  late InMemoryNotificationService notifications;
  late NotificationSettings settings;
  late NotificationCenter center;
  DateTime currentTime = DateTime(2026, 9, 1, 15); // 15h — hors plage silencieuse

  setUp(() async {
    db = (await LocalDatabase.openInMemory())!;
    currentTime = DateTime(2026, 9, 1, 15);
    gateway = FakeTelegramGateway(
      channels: [_channelA],
      messages: {
        _chatA: [
          _video(1001, _chatA, fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv'),
          _video(1002, _chatA, fileName: 'Solo.Leveling.S02E08.720p.VF.mkv'),
          _video(1003, _chatA, caption: 'Solo Leveling S02E08 480p VOSTFR'),
        ],
      },
    );
    service = LocalTelegramService(
      gateway: gateway,
      sessionManager: TelegramSessionManager(store: InMemoryKeyValueStore()),
      database: db,
    );
    notifications = InMemoryNotificationService();
    settings = NotificationSettings(database: db, now: () => currentTime);
    await settings.load();
    center = NotificationCenter(
      notifications: notifications,
      settings: settings,
      database: db,
      now: () => currentTime,
    );
    service.onSyncCompleted = center.handleSyncSummary;
    await settle();
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  Future<void> connectAndAdd({String username = 'anime_vf', String name = 'Anime VF', String? chatId}) async {
    await service.requestCode('+22912345678');
    await service.verifyCode('+22912345678', '12345');
    await service.addSource(name: name, username: username, channelId: chatId ?? '$_chatA');
  }

  group('Réglages persistés (règles 12/19/20)', () {
    test('fréquence, mode silencieux et heures silencieuses sont conservés', () async {
      await settings.setSyncFrequency(SyncFrequency.every30Minutes);
      await settings.setSilentMode(true);
      await settings.setQuietHoursEnabled(true);
      await settings.setQuietHours(startMinutes: 22 * 60 + 30, endMinutes: 6 * 60 + 45);

      final NotificationSettings reloaded = NotificationSettings(database: db);
      await reloaded.load();
      expect(reloaded.syncFrequency, SyncFrequency.every30Minutes);
      expect(reloaded.silentMode, isTrue);
      expect(reloaded.quietHoursEnabled, isTrue);
      expect(reloaded.quietStartMinutes, 22 * 60 + 30);
      expect(reloaded.quietEndMinutes, 6 * 60 + 45);
    });

    test('heures silencieuses : plage qui enjambe minuit', () {
      expect(settings.isInQuietHours(DateTime(2026, 9, 1, 15)), isFalse);
      settings.setQuietHoursEnabled(true);
      settings.setQuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60);
      expect(settings.isInQuietHours(DateTime(2026, 9, 1, 23, 30)), isTrue);
      expect(settings.isInQuietHours(DateTime(2026, 9, 1, 2, 15)), isTrue);
      expect(settings.isInQuietHours(DateTime(2026, 9, 1, 12)), isFalse);
    });

    test('plage vide (début = fin) : jamais silencieux', () {
      settings.setQuietHoursEnabled(true);
      settings.setQuietHours(startMinutes: 8 * 60, endMinutes: 8 * 60);
      expect(settings.isInQuietHours(DateTime(2026, 9, 1, 9)), isFalse);
    });

    test('setSyncFrequency applique la fréquence au planificateur', () async {
      final InMemoryAutoSyncScheduler scheduler = InMemoryAutoSyncScheduler();
      settings.attachScheduler(scheduler);
      await settings.setSyncFrequency(SyncFrequency.hourly);
      expect(scheduler.applied, SyncFrequency.hourly);
      await settings.setSyncFrequency(SyncFrequency.disabled);
      expect(scheduler.applied, SyncFrequency.disabled);
    });
  });

  group('Résumé réel de synchronisation (règles 16/21)', () {
    test('résumé complet : sources, messages, épisodes, qualités, erreurs', () async {
      await connectAndAdd();
      await service.syncAll();

      final SyncRunSummary? summary = service.lastSyncSummary;
      expect(summary, isNotNull);
      expect(summary!.sourcesAnalyzed, 1);
      expect(summary.newMessages, 3);
      expect(summary.newEpisodes, 1);
      expect(summary.newQualities, 2);
      expect(summary.errors, 0);
      expect(summary.episodes.length, 1);
      expect(summary.episodes.single.totalQualities, 3);
      expect(summary.episodes.single.isNewEpisode, isTrue);
    });

    test('règle 16 : une source désactivée n\'est jamais synchronisée', () async {
      gateway.channels.add(_channelB);
      gateway.messages[_chatB] = [
        _video(2001, _chatB, fileName: 'Jujutsu.Kaisen.S03E01.1080p.VOSTFR.mkv'),
      ];
      await connectAndAdd();
      await service.addSource(name: 'Anime VOSTFR', username: 'anime_vostfr', channelId: '$_chatB');
      final String disabledId = service.sources
          .firstWhere((s) => s.username == 'anime_vostfr')
          .id;
      await service.setSourceEnabled(disabledId, false);

      gateway.callLog.clear();
      await service.syncAll();

      final SyncRunSummary summary = service.lastSyncSummary!;
      expect(summary.sourcesAnalyzed, 1);
      // Aucune récupération sur le chat de la source désactivée.
      expect(
        gateway.callLog.where((String c) => c.startsWith('getMessages:$_chatB')),
        isEmpty,
      );
      // Seule la source active est passée en lastSync.
      expect(service.sources.firstWhere((s) => s.username == 'anime_vf').lastSync, isNotNull);
      expect(service.sources.firstWhere((s) => s.username == 'anime_vostfr').lastSync, isNull);
    });

    test('toutes les sources en échec → erreur globale claire', () async {
      await connectAndAdd();
      gateway.failOnNextFetch = const GatewayError('Telegram met trop de temps à répondre. Réessayez.');
      await expectLater(service.syncAll(), throwsA(isA<ApiException>()));
    });
  });

  group('Notifications nouveaux épisodes (règles 4/5/6)', () {
    test('un nouvel épisode déclenche une notification réelle', () async {
      await connectAndAdd();
      await service.syncAll();
      await settle();

      expect(notifications.history.length, 1);
      final ShownNotification shown = notifications.history.single;
      expect(shown.title, 'Nouvel épisode disponible');
      expect(shown.body, contains('Solo Leveling'));
      expect(shown.body, contains('S02E08'));
      expect(shown.channel, AppNotificationChannel.newEpisodes);
    });

    test('règle 5 : 3 qualités = 1 seule notification (« 3 qualités disponibles »)', () async {
      await connectAndAdd();
      await service.syncAll();
      await settle();

      expect(notifications.history.length, 1, reason: 'jamais 3 alertes pour 3 qualités');
      expect(notifications.history.single.body, contains('3 qualités disponibles'));
    });

    test('règle 6 : aucune nouvelle publication → aucune nouvelle notification', () async {
      await connectAndAdd();
      await service.syncAll();
      await settle();
      final int after = notifications.history.length;

      await service.syncAll(); // même contenu — synchronisation incrémentale
      await settle();
      expect(notifications.history.length, after);
    });

    test('une qualité de plus sur un épisode notifié met à jour la MÊME notification', () async {
      await connectAndAdd();
      await service.syncAll();
      await settle();
      final int id = notifications.history.single.id;

      gateway.messages[_chatA] = [
        ...gateway.messages[_chatA]!,
        _video(1004, _chatA, fileName: 'Solo.Leveling.S02E08.2160p.VF.mkv'),
      ];
      await service.syncAll();
      await settle();

      expect(notifications.history.length, 2);
      final ShownNotification update = notifications.history.last;
      expect(update.id, id, reason: 'même identifiant = mise à jour en place');
      expect(update.body, contains('4 qualités disponibles'));
    });

    test('un nouvel épisode incrémental déclenche sa propre notification', () async {
      await connectAndAdd();
      await service.syncAll();
      await settle();

      gateway.messages[_chatA] = [
        ...gateway.messages[_chatA]!,
        _video(1005, _chatA, fileName: 'Solo.Leveling.S02E09.1080p.VF.mkv'),
      ];
      await service.syncAll();
      await settle();

      expect(notifications.history.length, 2);
      expect(notifications.history.last.body, contains('S02E09'));
      // La persistance anti-doublon couvre aussi le redémarrage.
      expect(await db.getNotifiedEpisode('solo-leveling-s2-e9'), isNotNull);
    });

    test('règle 17 : notifications désactivées pour la source → silence', () async {
      await connectAndAdd();
      await settings.setSourceNotificationsEnabled(service.sources.single.id, false);
      await service.syncAll();
      await settle();
      expect(notifications.history, isEmpty);
    });

    test('règle 18 : notifications désactivées pour l\'animé → silence, catalogue intact', () async {
      await connectAndAdd();
      // Préférence basculée AVANT la passe, sur l'identifiant (slug) de
      // l'animé — sans le retirer du catalogue (règle 18).
      await db.upsertAnime(<String, Object?>{
        'id': 'solo-leveling',
        'title': 'Solo Leveling',
        'genres': '[]',
        'created_at': DateTime(2026, 9, 1).toIso8601String(),
        'notifications_enabled': 0,
      });
      await settings.setAnimeNotificationsEnabled('solo-leveling', false);
      await service.syncAll();
      await settle();
      expect(notifications.history, isEmpty);
      // L'animé est quand même référencé localement (règle 18).
      expect(await db.getAnime('solo-leveling'), isNotNull);
    });

    test('règle 19 : mode silencieux → canal discret', () async {
      await settings.setSilentMode(true);
      await connectAndAdd();
      await service.syncAll();
      await settle();
      expect(notifications.history.single.channel, AppNotificationChannel.newEpisodesSilent);
    });

    test('règle 20 : heures silencieuses → canal discret, alerte toujours créée', () async {
      await settings.setQuietHoursEnabled(true);
      await settings.setQuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60);
      currentTime = DateTime(2026, 9, 1, 2, 30); // en pleine plage
      await connectAndAdd();
      await service.syncAll();
      await settle();
      expect(notifications.history.single.channel, AppNotificationChannel.newEpisodesSilent);
    });

    test('aucune publication utile → aucune notification (jamais de fausse alerte)', () async {
      gateway.messages[_chatA] = [_video(1001, _chatA, caption: 'Discussion sans vidéo classable')];
      await connectAndAdd();
      await service.syncAll();
      await settle();
      expect(notifications.history, isEmpty);
    });
  });

  group('Clic sur notification (règle 7)', () {
    test('ouvrir une notification épisode appelle la navigation ciblée', () async {
      (String, String, String)? opened;
      center.onOpenEpisode = (String a, String s, String e) => opened = (a, s, e);
      await connectAndAdd();
      await service.syncAll();
      await settle();

      final ShownNotification shown = notifications.history.single;
      await center.handleNotificationTap(null, shown.payload);
      expect(opened, isNotNull);
      expect(opened!.$1, 'solo-leveling');
      expect(opened!.$2, 'solo-leveling-s2');
      expect(opened!.$3, 'solo-leveling-s2-e8');
    });

    test('charge utile illisible : aucun plantage', () async {
      (String, String, String)? opened;
      center.onOpenEpisode = (String a, String s, String e) => opened = (a, s, e);
      await center.handleNotificationTap(null, 'données corrompues');
      await center.handleNotificationTap(null, null);
      expect(opened, isNull);
    });
  });

  group('Notifications de téléchargement (règles 8/9/10)', () {
    test('progression réelle : valeurs mesurées, alerte unique', () async {
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.progress, _task(DownloadStatus.downloading)),
      );
      expect(notifications.history.length, 1);
      final ShownNotification progress = notifications.history.single;
      expect(progress.title, 'Téléchargement en cours');
      expect(progress.progress, 500);
      expect(progress.progressMax, 1000);
      expect(progress.ongoing, isTrue);
      expect(progress.onlyAlertOnce, isTrue);

      // < 4 s : aucune mise à jour supplémentaire (anti-spam).
      currentTime = currentTime.add(const Duration(seconds: 1));
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.progress, _task(DownloadStatus.downloading, downloaded: 700)),
      );
      expect(notifications.history.length, 1);

      // Après l'intervalle : mise à jour en place.
      currentTime = currentTime.add(const Duration(seconds: 5));
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.progress, _task(DownloadStatus.downloading, downloaded: 700)),
      );
      expect(notifications.history.length, 2);
      expect(notifications.history.last.id, progress.id);
      expect(notifications.history.last.progress, 700);
    });

    test('taille inconnue → aucune fausse progression', () async {
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.progress, _task(DownloadStatus.downloading, expected: null)),
      );
      expect(notifications.history, isEmpty);
    });

    test('règle 9 : terminé → « Téléchargement terminé » + action Lire', () async {
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.completed, _task(DownloadStatus.completed, downloaded: 1000)),
      );
      final ShownNotification done = notifications.history.single;
      expect(done.title, 'Téléchargement terminé');
      expect(done.body, contains('Solo Leveling'));
      expect(done.body, contains('S02E08'));
      expect(done.actions.map((a) => a.id), contains(NotificationActions.play));
    });

    test('clic « Lire » → ouverture du lecteur sur le bon épisode', () async {
      (String, String)? played;
      center.onPlayDownload = (String a, String e) => played = (a, e);
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.completed, _task(DownloadStatus.completed, downloaded: 1000)),
      );
      final ShownNotification done = notifications.history.single;
      await center.handleNotificationTap(NotificationActions.play, done.payload);
      expect(played, ('solo-leveling', 'solo-leveling-s2-e8'));
    });

    test('règle 10 : échec → « Téléchargement interrompu » + action Reprendre', () async {
      await center.handleDownloadEvent(
        DownloadEvent(
          DownloadEventKind.failed,
          _task(DownloadStatus.failed, error: 'Plus de connexion.', resumable: true),
        ),
      );
      final ShownNotification failed = notifications.history.single;
      expect(failed.title, 'Téléchargement interrompu');
      expect(failed.body, contains('Plus de connexion.'));
      expect(failed.actions.map((a) => a.id), contains(NotificationActions.resume));
    });

    test('« Reprendre » → reprise réelle du téléchargement', () async {
      String? resumed;
      center.onResumeDownload = (String versionId) async => resumed = versionId;
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.failed, _task(DownloadStatus.failed, resumable: true)),
      );
      final ShownNotification failed = notifications.history.single;
      await center.handleNotificationTap(NotificationActions.resume, failed.payload);
      expect(resumed, 'v1');
    });

    test('échec non reprenable → pas d\'action Reprendre', () async {
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.failed, _task(DownloadStatus.failed, resumable: false)),
      );
      expect(notifications.history.single.actions, isEmpty);
    });

    test('notifications de téléchargement désactivées → silence', () async {
      await settings.setDownloadNotificationsEnabled(false);
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.completed, _task(DownloadStatus.completed, downloaded: 1000)),
      );
      expect(notifications.history, isEmpty);
    });

    test('annulation → la notification de progression disparaît', () async {
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.progress, _task(DownloadStatus.downloading)),
      );
      currentTime = currentTime.add(const Duration(seconds: 5));
      await center.handleDownloadEvent(
        DownloadEvent(DownloadEventKind.cancelled, _task(DownloadStatus.cancelled, downloaded: 0)),
      );
      final int id = downloadNotificationId('v1');
      expect(notifications.shown[id], isNull);
      expect(notifications.cancelled, contains(id));
    });
  });

  group('Permission (règle 2)', () {
    test('le refus ne bloque jamais le reste de l\'application', () async {
      notifications.permissionGranted = false;
      expect(await notifications.isPermissionGranted(), isFalse);
      expect(await notifications.requestPermission(), isFalse);
      // L'application continue de fonctionner : la synchronisation
      // manuelle reste possible.
      await connectAndAdd();
      await service.syncAll();
      await settle();
      expect(service.lastSyncSummary, isNotNull);
    });
  });

  group('Session Telegram (règle 24)', () {
    test('session expirée → pas de synchronisation indéfinie', () async {
      await connectAndAdd();
      gateway.expireSession();
      await settle(30);
      await expectLater(
        service.syncAll(),
        throwsA(isA<ApiException>().having(
          (ApiException e) => e.kind,
          'kind',
          ApiErrorKind.unauthorized,
        )),
      );
    });
  });
}
