import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/anime/data/models/video_quality.dart';
import 'package:animebox/features/anime/data/repositories/local_anime_repository.dart';
import 'package:animebox/features/local/data/local_database.dart';
import 'package:animebox/features/telegram/data/gateway/telegram_gateway.dart';
import 'package:animebox/features/telegram/data/models/api_exception.dart';
import 'package:animebox/features/telegram/data/models/telegram_message.dart';
import 'package:animebox/features/telegram/data/services/local_telegram_service.dart';
import 'package:animebox/features/telegram/data/services/telegram_service.dart';
import 'package:animebox/features/telegram/data/services/telegram_session_manager.dart';

import 'step7_fake_gateway.dart';

const int _chatId = -1001234567890;

GatewayChat get _channel => const GatewayChat(
      id: _chatId,
      title: 'Anime VF',
      username: 'anime_vf',
      kind: GatewayChatKind.channel,
      memberCount: 12450,
    );

GatewayMessage _video(int id, {String? fileName, String? caption}) => GatewayMessage(
      messageId: id,
      chatId: _chatId,
      date: DateTime(2026, 9, 1, 10, id % 60),
      text: caption,
      mediaType: 'video',
      fileName: fileName,
      fileSize: 1400000000,
      mimeType: 'video/x-matroska',
      width: 1920,
      height: 1080,
      messageLink: telegramMessageLink(chatId: _chatId, messageId: id, username: 'anime_vf'),
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late LocalDatabase db;
  late FakeTelegramGateway gateway;
  late TelegramSessionManager sessions;
  late LocalTelegramService service;

  setUp(() async {
    db = (await LocalDatabase.openInMemory())!;
    gateway = FakeTelegramGateway(
      channels: [_channel],
      messages: {
        _chatId: [
          _video(1001, fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv'),
          _video(1002, fileName: 'Solo.Leveling.S02E08.720p.VF.mkv'),
          _video(1003, caption: 'Solo Leveling S02E08 480p VOSTFR'),
        ],
      },
    );
    sessions = TelegramSessionManager(store: InMemoryKeyValueStore());
    service = LocalTelegramService(
      gateway: gateway,
      sessionManager: sessions,
      database: db,
    );
    await settle();
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  Future<void> connect() async {
    await service.requestCode('+22912345678');
    expect(service.authState, TelegramAuthState.codeRequired);
    await service.verifyCode('+22912345678', '12345');
    expect(service.authState, TelegramAuthState.connected);
  }

  Future<void> addSource() async {
    await service.addSource(name: 'Anime VF', username: 'anime_vf', channelId: '$_chatId');
    expect(service.sources.length, 1);
  }

  group('1. Connexion Telegram', () {
    test('code requis puis connecté, profil chargé', () async {
      await connect();
      expect(service.currentUser?.username, 'test_user');
      expect(service.authError, isNull);
    });

    test('mot de passe 2FA requis puis vérifié', () async {
      gateway.requirePassword = true;
      await service.requestCode('+22912345678');
      await service.verifyCode('+22912345678', '12345');
      expect(service.authState, TelegramAuthState.passwordRequired);
      await service.requestPassword('motdepasse2fa');
      expect(service.authState, TelegramAuthState.connected);
    });

    test('code incorrect → message clair, pas de secret', () async {
      await service.requestCode('+22912345678');
      await expectLater(
        service.verifyCode('+22912345678', '00000'),
        throwsA(isA<GatewayError>()),
      );
      expect(service.authError, 'Code de connexion incorrect.');
    });
  });

  group('2. Restauration de session', () {
    test('session enregistrée → reconnexion automatique', () async {
      await connect();
      await sessions.markConnected(true);
      gateway.autoConnectOnCreate = true;

      final LocalTelegramService restored = LocalTelegramService(
        gateway: FakeTelegramGateway(channels: [_channel], autoConnectOnCreate: true),
        sessionManager: sessions,
        database: db,
      );
      await settle();
      expect(restored.authState, TelegramAuthState.connected);
      expect(restored.currentUser, isNotNull);
      restored.dispose();
    });

    test('aucune session → état déconnecté', () async {
      final LocalTelegramService fresh = LocalTelegramService(
        gateway: FakeTelegramGateway(),
        sessionManager: TelegramSessionManager(store: InMemoryKeyValueStore()),
        database: db,
      );
      await settle();
      expect(fresh.authState, TelegramAuthState.disconnected);
      fresh.dispose();
    });
  });

  group('3. Déconnexion', () {
    test('disconnect efface la session et repasse déconnecté', () async {
      await connect();
      await service.disconnect();
      expect(service.authState, TelegramAuthState.disconnected);
      expect(service.currentUser, isNull);
      expect(await sessions.wasConnected(), isFalse);
      expect(gateway.callLog, contains('logout'));
    });
  });

  group('4-6. Ajout / accessibilité / suppression', () {
    test('canal public accessible → ajout', () async {
      await connect();
      final resolved = await service.resolveChannel('@anime_vf');
      expect(resolved.title, 'Anime VF');
      expect(resolved.memberCount, 12450);
      await addSource();
      expect(service.sourceById(service.sources.first.id), isNotNull);
    });

    test('canal inaccessible → message explicite', () async {
      await connect();
      await expectLater(
        service.resolveChannel('@canal_inconnu'),
        throwsA(isA<ApiException>().having(
          (ApiException e) => e.displayMessage,
          'message',
          'Ce canal n\'est pas accessible avec ce compte Telegram.',
        )),
      );
    });

    test('suppression d\'une source (confirmée côté interface)', () async {
      await connect();
      await addSource();
      final String id = service.sources.first.id;
      await service.removeSource(id);
      expect(service.sources, isEmpty);
    });
  });

  group('7-8. Récupération des messages + pagination', () {
    test('messages mappés avec références Telegram', () async {
      await connect();
      await addSource();
      final List<TelegramMessage> messages = await service.fetchMessages(service.sources.first.id, limit: 2);
      expect(messages.length, 2);
      expect(messages.first.messageId, 1003); // plus récent d'abord
      expect(messages.first.text, isNotNull); // caption conservée
      expect(messages.first.messageLink, contains('t.me/anime_vf/1003'));
    });

    test('pagination : fromMessageId renvoie la page antérieure', () async {
      final List<GatewayMessage> page1 = await gateway.getMessages(chatId: _chatId, limit: 2);
      expect(page1.map((GatewayMessage m) => m.messageId).toList(), [1003, 1002]);
      final List<GatewayMessage> page2 = await gateway.getMessages(chatId: _chatId, limit: 2, fromMessageId: 1002);
      expect(page2.map((GatewayMessage m) => m.messageId).toList(), [1001]);
    });
  });

  group('9. Synchronisation initiale (scénario §16)', () {
    test('3 publications → 1 anime, 1 saison, 1 épisode, 3 versions', () async {
      await connect();
      await addSource();
      await service.syncSource(sourceId: service.sources.first.id);

      final LocalAnimeRepository repository = LocalAnimeRepository(database: db);
      await repository.reloadFromDatabase();

      final anime = repository.byId('solo-leveling');
      expect(anime, isNotNull, reason: 'la fiche Solo Leveling doit exister');
      expect(anime!.seasons.length, 1);
      final season = anime.seasons.first;
      expect(season.number, 2);
      expect(season.episodes.length, 1);
      final episode = season.episodes.first;
      expect(episode.number, 8);
      expect(episode.title, isNull, reason: 'jamais de titre inventé');
      expect(episode.qualities.length, 3, reason: 'trois qualités regroupées');
      expect(episode.qualities.map((q) => q.quality.label).toSet(), {'1080p', '720p', '480p'});

      // Statistiques de la source mises à jour.
      final source = service.sources.first;
      expect(source.analyzedPosts, 3);
      expect(source.detectedEpisodes, 1);
      expect(source.lastSync, isNotNull);
    });
  });

  group('10. Synchronisation incrémentale', () {
    test('seuls les nouveaux messages sont analysés', () async {
      await connect();
      await addSource();
      await service.syncSource(sourceId: service.sources.first.id);

      // Nouvelle publication #1004 après le curseur #1003.
      gateway.messages[_chatId] = [
        ...gateway.messages[_chatId]!,
        _video(1004, fileName: 'Solo Leveling S02E09 1080p VF.mkv'),
      ];
      await service.syncSource(sourceId: service.sources.first.id);

      final source = service.sources.first;
      expect(source.analyzedPosts, 4); // 3 + 1 (pas de réanalyse des anciens)
      expect(source.detectedEpisodes, 2);

      final LocalAnimeRepository repository = LocalAnimeRepository(database: db);
      await repository.reloadFromDatabase();
      final anime = repository.byId('solo-leveling')!;
      expect(anime.seasons.first.episodes.length, 2, reason: 'un épisode 9 ajouté, pas de doublon');
    });
  });

  group('11-13. Analyse locale, regroupement, références', () {
    test('références Telegram conservées sur chaque version', () async {
      await connect();
      await addSource();
      await service.syncSource(sourceId: service.sources.first.id);

      final LocalAnimeRepository repository = LocalAnimeRepository(database: db);
      await repository.reloadFromDatabase();
      final episode = repository.byId('solo-leveling')!.seasons.first.episodes.first;
      final List<int?> ids = episode.qualities.map((q) => q.telegramMessageId).toList();
      expect(ids.whereType<int>().toSet(), {1001, 1002, 1003});
      expect(episode.qualities.every((q) => q.telegramMessageLink != null), isTrue);
      expect(episode.qualities.first.sourceChannelUsername, 'anime_vf');
    });
  });

  group('14. Hors-ligne', () {
    test('panne réseau → message clair, catalogue intact', () async {
      await connect();
      await addSource();
      await service.syncSource(sourceId: service.sources.first.id);

      gateway.failOnNextFetch = const GatewayError('Pas de connexion Internet. Vérifiez votre réseau.');

      await expectLater(
        service.syncSource(sourceId: service.sources.first.id),
        throwsA(isA<ApiException>()),
      );

      // Le catalogue local n'est PAS vidé.
      final LocalAnimeRepository repository = LocalAnimeRepository(database: db);
      await repository.reloadFromDatabase();
      expect(repository.byId('solo-leveling'), isNotNull);
      // La source passe en erreur avec un statut lisible.
      expect(service.sources.first.status.name, 'error');
    });
  });

  group('15. Session expirée', () {
    test('révocation distante → état expired', () async {
      await connect();
      gateway.expireSession();
      await Future<void>.delayed(Duration.zero);
      expect(service.authState, TelegramAuthState.expired);
      expect(service.authError, contains('expiré'));
    });
  });

  group('16. Erreur réseau', () {
    test('timeout/erreur pendant la récupération → ApiException lisible', () async {
      await connect();
      await addSource();
      gateway.failOnNextFetch = const GatewayError('Telegram met trop de temps à répondre. Réessayez.');
      await expectLater(
        service.syncSource(sourceId: service.sources.first.id),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('17. Annulation d\'une synchronisation', () {
    test('cancel() arrête proprement sans corrompre le catalogue', () async {
      await connect();
      await addSource();
      // Beaucoup de messages pour que la synchro soit annulable.
      gateway.messages[_chatId] = [
        for (int i = 1; i <= 300; i++)
          _video(i, fileName: 'Solo Leveling S02E${(i % 13) + 1} 1080p VF.mkv'),
      ];
      gateway.delayPerFetch = const Duration(milliseconds: 25);

      final Future<void> sync = service.syncSource(sourceId: service.sources.first.id);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await service.cancelSync();
      await sync;

      // L'annulation est tracée dans l'historique.
      await service.loadStats();
      expect(service.history.first.success, isFalse);
      expect(service.isSyncing, isFalse);
    });
  });
}
