import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/anime/data/repositories/local_anime_repository.dart';
import 'package:animebox/features/local/data/local_database.dart';
import 'package:animebox/features/telegram/data/gateway/telegram_gateway.dart';
import 'package:animebox/features/telegram/data/models/api_exception.dart';
import 'package:animebox/features/telegram/data/models/telegram_source.dart';
import 'package:animebox/features/telegram/data/services/local_telegram_service.dart';
import 'package:animebox/features/telegram/data/services/telegram_service.dart';
import 'package:animebox/features/telegram/data/services/telegram_session_manager.dart';

import 'step7_fake_gateway.dart';

const int _chatA = -1001234567890;
const int _chatB = -1002222222220;

GatewayChat get _channelA => const GatewayChat(
      id: _chatA, title: 'Anime VF', username: 'anime_vf',
      kind: GatewayChatKind.channel, memberCount: 12450,
    );
GatewayChat get _channelB => const GatewayChat(
      id: _chatB, title: 'Animes HD', username: 'animes_hd',
      kind: GatewayChatKind.channel, memberCount: 8000,
    );

GatewayMessage _video(int chatId, String username, int id, {String? fileName}) => GatewayMessage(
      messageId: id,
      chatId: chatId,
      date: DateTime(2026, 9, 1, 10, id % 60),
      mediaType: 'video',
      fileName: fileName,
      fileSize: 700000000,
      mimeType: 'video/x-matroska',
      messageLink: telegramMessageLink(chatId: chatId, messageId: id, username: username),
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
      channels: [_channelA, _channelB],
      messages: {
        _chatA: [
          _video(_chatA, 'anime_vf', 1001, fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv'),
        ],
        _chatB: [
          _video(_chatB, 'animes_hd', 5001, fileName: 'Jujutsu.Kaisen.S03E04.720p.VOSTFR.mkv'),
        ],
      },
      usersByPhone: const {
        '+22912345678': GatewayUser(firstName: 'Premier', lastName: 'Compte', username: 'compte_a'),
        '+33123456789': GatewayUser(firstName: 'Second', lastName: 'Compte', username: 'compte_b'),
      },
    );
    sessions = TelegramSessionManager(store: InMemoryKeyValueStore());
    service = LocalTelegramService(gateway: gateway, sessionManager: sessions, database: db);
    await settle();
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  Future<void> connect([String phone = '+22912345678']) async {
    await service.requestCode(phone);
    await service.verifyCode(phone, '12345');
  }

  Future<TelegramSource> addSourceA() async {
    await service.addSource(name: 'Anime VF', username: 'anime_vf', channelId: '$_chatA');
    return service.sources.firstWhere((s) => s.username == 'anime_vf');
  }

  group('2/3/4. Connexion code + 2FA (rappel)', () {
    test('code correct → connecté, profil chargé', () async {
      await connect();
      expect(service.authState, TelegramAuthState.connected);
      expect(service.currentUser?.username, 'compte_a');
    });

    test('code incorrect → message clair, aucun secret exposé', () async {
      await service.requestCode('+22912345678');
      await expectLater(
        service.verifyCode('+22912345678', '99999'),
        throwsA(isA<GatewayError>()),
      );
      expect(service.authError, contains('incorrect'));
      expect(service.authError, isNot(contains('99999')), reason: '§26 : jamais de code dans les messages');
    });

    test('2FA : mot de passe demandé uniquement quand Telegram l\'exige', () async {
      gateway.requirePassword = true;
      await service.requestCode('+22912345678');
      await service.verifyCode('+22912345678', '12345');
      expect(service.authState, TelegramAuthState.passwordRequired,
          reason: 'le mot de passe est demandé SEUL quand Telegram le demande');
      await service.requestPassword('motdepasse2fa');
      expect(service.authState, TelegramAuthState.connected);
    });
  });

  group('13. Activation / désactivation (§13)', () {
    test('source désactivée : plus synchronisée automatiquement, reste visible', () async {
      await connect();
      final TelegramSource source = await addSourceA();
      await service.setSourceEnabled(source.id, false);
      expect(service.sources.single.syncEnabled, isFalse);

      gateway.callLog.clear();
      await service.syncAll();
      expect(gateway.callLog.where((String e) => e.startsWith('getMessages:$_chatA')), isEmpty,
          reason: 'jamais interrogée par la synchronisation automatique');
      expect(service.lastSyncSummary?.sourcesAnalyzed, 0, reason: 'chiffres réels : aucune source traitée');
      expect(service.sources.length, 1, reason: 'la source reste visible dans la liste');
    });

    test('réactivation → la synchronisation fonctionne de nouveau', () async {
      await connect();
      final TelegramSource source = await addSourceA();
      await service.setSourceEnabled(source.id, false);
      await service.setSourceEnabled(source.id, true);
      gateway.callLog.clear();
      await service.syncAll();
      expect(gateway.callLog.any((String e) => e.startsWith('getMessages:$_chatA')), isTrue);
    });
  });

  group('14. Suppression : ni catalogue, ni favoris, ni historique, ni téléchargements', () {
    test('removeSource conserve les données locales', () async {
      await connect();
      final TelegramSource source = await addSourceA();
      await service.syncSource(sourceId: source.id);

      // Données utilisateur construites sur le catalogue détecté.
      final LocalAnimeRepository repo = LocalAnimeRepository(database: db);
      await repo.reloadFromDatabase();
      repo.toggleFavorite('solo-leveling');
      final String e8 = repo.byId('solo-leveling')!.seasons.first.episodes.single.id;
      repo.recordProgress('solo-leveling', e8, const Duration(minutes: 4), duration: const Duration(minutes: 24));
      await settle();

      await service.removeSource(source.id);
      expect(service.sources, isEmpty);

      final LocalAnimeRepository after = LocalAnimeRepository(database: db);
      await after.reloadFromDatabase();
      expect(after.byId('solo-leveling'), isNotNull, reason: 'les animés détectés restent');
      expect(after.libraryEntryFor('solo-leveling')?.isFavorite, isTrue, reason: 'favoris conservés');
      expect(after.episodeProgress('solo-leveling', e8), const Duration(minutes: 4),
          reason: 'historique de lecture conservé');
      expect(await db.listDownloads(), isEmpty, reason: 'cas du test : aucun téléchargement à perdre');
    });
  });

  group('16. Synchronisation globale — chiffres réels (§16)', () {
    test('syncAll : 2 sources actives comptées réellement', () async {
      await connect();
      await addSourceA();
      await service.addSource(name: 'Animes HD', username: 'animes_hd', channelId: '$_chatB');
      await service.syncAll();

      final summary = service.lastSyncSummary!;
      expect(summary.sourcesAnalyzed, 2, reason: 'nombre réel de sources analysées');
      expect(summary.newMessages, 2, reason: 'nombre réel de nouvelles publications');
      expect(summary.errors, 0);
      expect(summary.finishedAt, isNotNull);
    });
  });

  group('24/25. Limitations et erreurs Telegram', () {
    test('FloodWait → message clair, jamais de boucle agressive', () async {
      await connect();
      final TelegramSource source = await addSourceA();
      gateway.failOnNextFetch = const GatewayError('FLOOD_WAIT_12', code: 429, isFlood: true);
      gateway.callLog.clear();

      await expectLater(
        service.syncSource(sourceId: source.id),
        throwsA(isA<ApiException>().having(
          (ApiException e) => e.displayMessage,
          'message',
          contains('Telegram limite temporairement cette opération'),
        )),
      );
      expect(gateway.callLog.where((String e) => e.startsWith('getMessages')).length, 1,
          reason: 'aucune boucle agressive : une seule tentative');
      expect(service.lastSyncSummary?.errors, 1);
    });
  });

  group('5/6/30. Session, déconnexion, changement de compte', () {
    test('déconnexion : sync arrêtée, résumé effacé, session supprimée, catalogue conservé', () async {
      await connect();
      final TelegramSource source = await addSourceA();
      await service.syncSource(sourceId: source.id);
      expect(service.lastSyncSummary, isNotNull);

      await service.disconnect();
      expect(service.isSyncing, isFalse);
      expect(service.lastSyncSummary, isNull, reason: '§6 : tout suivi de sync est arrêté');
      expect(service.sources.length, 1, reason: 'les sources AJOUTÉES restent (données locales conservées)');
      expect(await sessions.wasConnected(), isFalse);
      expect(service.currentUser, isNull);
      expect(service.authState, TelegramAuthState.disconnected);

      final LocalAnimeRepository repo = LocalAnimeRepository(database: db);
      await repo.reloadFromDatabase();
      expect(repo.allAnime, isNotEmpty, reason: 'le catalogue local est conservé après déconnexion');
    });

    test('changement de compte : nouveau profil réel, pas de mélange de session', () async {
      await connect();
      expect(service.currentUser?.username, 'compte_a');
      await service.disconnect();

      await connect('+33123456789');
      expect(service.currentUser?.username, 'compte_b', reason: 'le nouveau compte est réellement reconnu');
      expect(service.sources, isNotEmpty, reason: 'les sources locales persistent pour re-synchronisation');
    });

    test('session restaurée au redémarrage (§5/§29)', () async {
      await connect();
      await sessions.markConnected(true);
      final LocalTelegramService restored = LocalTelegramService(
        gateway: FakeTelegramGateway(channels: [_channelA], autoConnectOnCreate: true),
        sessionManager: sessions,
        database: db,
      );
      await settle();
      expect(restored.authState, TelegramAuthState.connected,
          reason: 'la session valide est restaurée sans re-demander le code');
      restored.dispose();
    });
  });

  group('8/9/10/11. Ajout de canaux', () {
    test('@username public résolu avec infos réelles avant ajout (§9)', () async {
      await connect();
      final resolved = await service.resolveChannel('@anime_vf');
      expect(resolved.title, 'Anime VF');
      expect(resolved.username, 'anime_vf');
      expect(resolved.memberCount, 12450);
    });

    test('lien t.me résolu de la même façon (§8)', () async {
      await connect();
      final resolved = await service.resolveChannel('https://t.me/animes_hd');
      expect(resolved.title, 'Animes HD');
    });

    test('canal inaccessible → message clair, jamais de contournement (§10/§11)', () async {
      await connect();
      await expectLater(
        service.resolveChannel('@canal_prive_inconnu'),
        throwsA(isA<ApiException>().having(
          (ApiException e) => e.displayMessage, 'message',
          contains('pas accessible'),
        )),
      );
      expect(service.sources, isEmpty, reason: 'aucune source ajoutée sans vérification (§8)');
    });

    test('ajout sans vérification impossible : username inconnu refusé', () async {
      await connect();
      await expectLater(
        service.addSource(name: 'Inconnu', username: 'canal_inconnu'),
        throwsA(isA<Exception>()),
      );
      expect(service.sources, isEmpty);
    });
  });
}
