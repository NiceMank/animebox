import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/anime/data/models/anime.dart';
import 'package:animebox/features/anime/data/models/playback_progress.dart';
import 'package:animebox/features/anime/data/models/video_quality.dart';
import 'package:animebox/features/anime/data/repositories/local_anime_repository.dart';
import 'package:animebox/features/local/data/local_database.dart';
import 'package:animebox/features/telegram/data/gateway/telegram_gateway.dart';
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

GatewayMessage _video(int chatId, String username, int id, {String? fileName, String? caption}) => GatewayMessage(
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
      messageLink: telegramMessageLink(chatId: chatId, messageId: id, username: username),
    );

List<GatewayMessage> _catalogueMessages() => [
      // Solo Leveling S02E08 — 3 qualités (un seul épisode).
      _video(_chatA, 'anime_vf', 1001, fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv'),
      _video(_chatA, 'anime_vf', 1002, fileName: 'Solo.Leveling.S02E08.720p.VF.mkv'),
      _video(_chatA, 'anime_vf', 1003, caption: 'Solo Leveling S02E08 480p VOSTFR'),
      // Solo Leveling S02E09 — une qualité.
      _video(_chatA, 'anime_vf', 1004, fileName: 'Solo.Leveling.S02E09.1080p.VF.mkv'),
      // Jujutsu Kaisen : 2 saisons (S01E12, S03E04).
      _video(_chatA, 'anime_vf', 1005, fileName: 'Jujutsu.Kaisen.S01E12.1080p.VF.mkv'),
      _video(_chatA, 'anime_vf', 1006, fileName: 'Jujutsu.Kaisen.S03E04.1080p.VF.mkv'),
    ];

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
      messages: {_chatA: _catalogueMessages(), _chatB: const []},
    );
    sessions = TelegramSessionManager(store: InMemoryKeyValueStore());
    service = LocalTelegramService(gateway: gateway, sessionManager: sessions, database: db);
    await settle();
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  Future<void> connectAndSync() async {
    await service.requestCode('+22912345678');
    await service.verifyCode('+22912345678', '12345');
    await service.addSource(name: 'Anime VF', username: 'anime_vf', channelId: '$_chatA');
    await service.syncSource(sourceId: service.sources.first.id);
  }

  Future<LocalAnimeRepository> openRepo() async {
    final LocalAnimeRepository repo = LocalAnimeRepository(database: db);
    await repo.reloadFromDatabase();
    return repo;
  }

  group('1 & 34. Bibliothèque réelle, aucune donnée fictive', () {
    test('base vierge → catalogue vide (jamais de catalogue de démonstration)', () async {
      final LocalAnimeRepository repo = await openRepo();
      expect(repo.allAnime, isEmpty, reason: '§34 : aucun animé inventé au premier lancement');
      expect(repo.libraryEntries, isEmpty);
      expect(repo.watchHistory, isEmpty);
    });

    test('après synchronisation : les animés détectés réels apparaissent', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      expect(repo.allAnime.length, 2, reason: 'Solo Leveling + Jujutsu Kaisen réellement détectés');
      expect(repo.byId('solo-leveling'), isNotNull);
      expect(repo.byId('jujutsu-kaisen'), isNotNull);
      expect(repo.byId('naruto'), isNull, reason: 'jamais ajouté automatiquement (§34)');
    });
  });

  group('3-4. Recherche locale', () {
    test('recherche « solo » → Solo Leveling (tolérante à la casse)', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final List<Anime> results = repo.search('solo');
      expect(results.length, 1);
      expect(results.first.id, 'solo-leveling');
      expect(repo.search('SOLO LEVELING').first.id, 'solo-leveling');
    });

    test('recherche sans résultat → liste vide, jamais d\'animé inventé', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      expect(repo.search('hxh'), isEmpty);
    });

    test('titre alternatif/original couvert de la même façon', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      expect(repo.search('leveling').single.id, 'solo-leveling');
    });
  });

  group('2. Tri', () {
    test('tri A → Z puis Z → A', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final List<Anime> asc = List.of(repo.allAnime)
        ..sort((Anime a, Anime b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      expect(asc.first.id, 'jujutsu-kaisen');
      final List<Anime> desc = List.of(asc)..sort((Anime a, Anime b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
      expect(desc.first.id, 'solo-leveling');
    });

    test('tri par date : l\'épisode le plus récent d\'abord', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final List<Anime> byDate = List.of(repo.allAnime)
        ..sort((Anime a, Anime b) {
          final DateTime da = a.latestEpisode?.date ?? DateTime(1970);
          final DateTime db_ = b.latestEpisode?.date ?? DateTime(1970);
          return db_.compareTo(da);
        });
      // Msg 1006 (Jujutsu S03E04) est publié après les Solo Leveling.
      expect(byDate.first.id, 'jujutsu-kaisen');
    });
  });

  group('7-8 & 27. Favoris persistant', () {
    test('ajouter/retirer un favori, survit au redémarrage', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      repo.toggleFavorite('solo-leveling');
      expect(repo.libraryEntryFor('solo-leveling')?.isFavorite, isTrue);
      await settle();

      // « Redémarrage » : nouveau dépôt sur la même base.
      final LocalAnimeRepository restarted = await openRepo();
      expect(restarted.libraryEntryFor('solo-leveling')?.isFavorite, isTrue,
          reason: 'le favori est persisté dans SQLite (§27)');

      restarted.toggleFavorite('solo-leveling');
      expect(restarted.libraryEntryFor('solo-leveling')?.isFavorite, isFalse);
    });
  });

  group('10-11-17. Progression et épisodes terminés', () {
    test('progression réelle enregistrée : position, durée, pourcentage', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final Anime anime = repo.byId('solo-leveling')!;
      final String episodeId = anime.seasons.first.episodes
          .firstWhere((e) => e.number == 8)
          .id;
      repo.recordProgress('solo-leveling', episodeId, const Duration(minutes: 12),
          duration: const Duration(minutes: 24));
      expect(repo.episodeProgress('solo-leveling', episodeId), const Duration(minutes: 12));

      final PlaybackProgress? entry = repo.watchHistory.isNotEmpty ? repo.watchHistory.first : null;
      expect(entry, isNotNull);
      expect(entry!.fraction.roundToDouble(), 0.5, reason: 'pourcentage déduit de données réelles');
      expect(entry.completed, isFalse);
    });

    test('épisode terminé marqué, relu depuis le début, jamais retiré de l\'historique', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final String episodeId = repo.byId('solo-leveling')!.seasons.first.episodes
          .firstWhere((e) => e.number == 8).id;
      repo.recordProgress('solo-leveling', episodeId, const Duration(minutes: 24),
          duration: const Duration(minutes: 24), completed: true);
      expect(repo.episodeCompleted('solo-leveling', episodeId), isTrue);
      expect(repo.watchHistory.any((PlaybackProgress p) => p.episodeId == episodeId), isTrue,
          reason: '§11 : un épisode terminé reste dans l\'historique');
    });
  });

  group('9 & 16. Continuer à regarder puis reprise', () {
    test('dernier épisode relu proposé à la reprise', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final Anime anime = repo.byId('solo-leveling')!;
      final String e8 = anime.seasons.first.episodes.firstWhere((e) => e.number == 8).id;
      repo.recordProgress('solo-leveling', e8, const Duration(minutes: 5), duration: const Duration(minutes: 24));
      final entry = repo.libraryEntryFor('solo-leveling');
      expect(entry?.resumeEpisodeId, e8);
      expect(entry?.resumePosition, const Duration(minutes: 5));
    });
  });

  group('12-14. Historique et effacement ciblé', () {
    test('historique global trié du plus récent au plus ancien, dates réelles', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final Anime anime = repo.byId('solo-leveling')!;
      final List episodes = anime.seasons.first.episodes;
      final String e8 = episodes.firstWhere((e) => e.number == 8).id;
      final String e9 = episodes.firstWhere((e) => e.number == 9).id;
      repo.recordProgress('solo-leveling', e8, const Duration(minutes: 3), duration: const Duration(minutes: 24));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      repo.recordProgress('solo-leveling', e9, const Duration(minutes: 6), duration: const Duration(minutes: 24));

      final List<PlaybackProgress> history = repo.watchHistory;
      expect(history.length, 2);
      expect(history.first.episodeId, e9, reason: 'plus récent d\'abord');
      expect(history.first.savedAt.isAfter(history.last.savedAt), isTrue);
      expect(history.first.duration, const Duration(minutes: 24), reason: 'durée réelle conservée');
    });

    test('effacer l\'historique : ni favoris, ni versions, ni téléchargements touchés', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      repo.toggleFavorite('solo-leveling');
      final String e8 = repo.byId('solo-leveling')!.seasons.first.episodes
          .firstWhere((e) => e.number == 8).id;
      repo.recordProgress('solo-leveling', e8, const Duration(minutes: 3), duration: const Duration(minutes: 24));
      await settle();

      repo.clearWatchHistory();
      expect(repo.watchHistory, isEmpty);
      expect(repo.episodeProgress('solo-leveling', e8), isNull, reason: 'progressions effacées');
      expect(repo.libraryEntryFor('solo-leveling')?.isFavorite, isTrue, reason: 'favoris conservés');
      expect(repo.byId('solo-leveling')!.seasons.first.episodes.length, 2, reason: 'épisodes conservés');
      expect(service.sources.length, 1, reason: 'sources Telegram conservées');
      expect((await db.loadFavorites()).contains('solo-leveling'), isTrue);

      // La base progress est vidée de façon persistante.
      await settle();
      expect(await db.loadProgress(), isEmpty);
    });
  });

  group('15 & 21. Nouveautés réelles, dédupliquées par épisode', () {
    test('un épisode en 3 qualités = UNE nouveauté (ordre récent)', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final List<String> recents = repo.recentEpisodeIds;
      expect(recents, contains('solo-leveling'));
      expect(recents.toSet().length, recents.length, reason: 'pas de doublon de fiche');
      // Jujutsu a aussi des épisodes détectés récents.
      expect(recents, contains('jujutsu-kaisen'));
    });
  });

  group('17-19-25. Saisons, qualités, mises à jour', () {
    test('deux saisons séparées, jamais mélangées', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final Anime anime = repo.byId('jujutsu-kaisen')!;
      expect(anime.seasons.length, 2);
      expect(anime.seasons.map((s) => s.number).toSet(), {1, 3});
    });

    test('qualités regroupées : 1 épisode = 3 versions', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      final episode = repo.byId('solo-leveling')!.seasons.first.episodes
          .firstWhere((e) => e.number == 8);
      expect(episode.qualities.length, 3);
      expect(episode.qualities.map((q) => q.quality.label).toSet(), {'1080p', '720p', '480p'});
    });

    test('nouvelle qualité détectée → épisode mis à jour, pas de doublon', () async {
      await connectAndSync();
      gateway.messages[_chatA] = [
        ...gateway.messages[_chatA]!,
        _video(_chatA, 'anime_vf', 1007, fileName: 'Solo.Leveling.S02E08.2160p.VF.mkv'),
      ];
      await service.syncSource(sourceId: service.sources.first.id);
      final LocalAnimeRepository repo = await openRepo();
      final anime = repo.byId('solo-leveling')!;
      final e8 = anime.seasons.first.episodes.firstWhere((e) => e.number == 8);
      expect(e8.qualities.map((q) => q.quality.label).contains('2160p'), isTrue,
          reason: '§25 : l\'épisode existant est enrichi');
      expect(anime.seasons.first.episodes.where((e) => e.number == 8).length, 1, reason: 'pas de doublon');
    });

    test('doublons : la re-synchronisation ne crée rien de neuf', () async {
      await connectAndSync();
      await service.syncSource(sourceId: service.sources.first.id);
      final LocalAnimeRepository repo = await openRepo();
      expect(repo.allAnime.length, 2);
      expect(repo.byId('solo-leveling')!.seasons.length, 1);
    });
  });

  group('23. Redémarrage de l\'application', () {
    test('catalogue, progression, favoris et historique rechargés', () async {
      await connectAndSync();
      final LocalAnimeRepository repo = await openRepo();
      repo.toggleFavorite('solo-leveling');
      final String e8 = repo.byId('solo-leveling')!.seasons.first.episodes
          .firstWhere((e) => e.number == 8).id;
      repo.recordProgress('solo-leveling', e8, const Duration(minutes: 11), duration: const Duration(minutes: 24));
      await settle();

      final LocalAnimeRepository restarted = await openRepo();
      expect(restarted.allAnime.length, 2);
      expect(restarted.libraryEntryFor('solo-leveling')?.isFavorite, isTrue);
      expect(restarted.episodeProgress('solo-leveling', e8), const Duration(minutes: 11));
      expect(restarted.watchHistory.length, 1, reason: 'l\'historique survit au redémarrage');
      expect(restarted.libraryEntryFor('solo-leveling')?.resumeEpisodeId, e8);
    });
  });

  group('24. Sources multiples', () {
    test('même animé détecté sur 2 canaux → UNE fiche, versions cumulées', () async {
      await connectAndSync();
      gateway.messages[_chatB] = [
        _video(_chatB, 'animes_hd', 5001, fileName: 'Solo.Leveling.S02E08.720p.MULTI.mkv'),
      ];
      await service.addSource(name: 'Animes HD', username: 'animes_hd', channelId: '$_chatB');
      await service.syncSource(sourceId: service.sources.last.id);

      final LocalAnimeRepository repo = await openRepo();
      expect(repo.allAnime.where((a) => a.id == 'solo-leveling').length, 1,
          reason: '§24 : jamais plusieurs fiches pour le même animé');
      final e8 = repo.byId('solo-leveling')!.seasons.first.episodes
          .firstWhere((e) => e.number == 8);
      // Les référence de chaque source restent traçables (3+1 versions).
      expect(e8.qualities.length, 4, reason: 'versions de toutes les sources regroupées');
      final links = e8.qualities.map((q) => q.telegramMessageLink).whereType<String>().toSet();
      expect(links.any((String l) => l.contains('animes_hd')), isTrue, reason: 'référence de la 2ᵉ source conservée');
    });
  });

  group('22. Hors connexion', () {
    test('échec réseau : catalogue local intact et consultable', () async {
      await connectAndSync();
      gateway.failOnNextFetch = const GatewayError('Pas de connexion Internet. Vérifiez votre réseau.');
      await expectLater(
        service.syncSource(sourceId: service.sources.first.id),
        throwsA(isA<Exception>()),
      );
      final LocalAnimeRepository repo = await openRepo();
      expect(repo.allAnime.length, 2, reason: 'le catalogue local reste consultable hors ligne');
      expect(repo.search('solo').length, 1, reason: 'recherche disponible hors connexion');
    });
  });
}
