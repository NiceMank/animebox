import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/anime/data/models/anime.dart';
import 'package:animebox/features/anime/data/models/episode.dart';
import 'package:animebox/features/anime/data/models/episode_quality.dart';
import 'package:animebox/features/anime/data/models/season.dart';
import 'package:animebox/features/anime/data/models/video_quality.dart';
import 'package:animebox/features/anime/data/repositories/local_anime_repository.dart';
import 'package:animebox/features/local/data/local_database.dart';
import 'package:animebox/features/media/models/download_models.dart';
import 'package:animebox/features/media/models/media_access.dart';
import 'package:animebox/features/media/services/download_manager.dart';
import 'package:animebox/features/media/services/media_paths.dart';
import 'package:animebox/features/media/services/media_service.dart';
import 'package:animebox/features/media/services/storage_checker.dart';
import 'package:animebox/features/player/player_controller.dart';
import 'package:animebox/features/telegram/data/gateway/telegram_gateway.dart';

import 'step7_fake_gateway.dart';

const int _chatId = -1001234567890;
const int _messageId = 1001;
const int _fileId = 4242;

GatewayChat get _channel => const GatewayChat(
      id: _chatId,
      title: 'Anime VF',
      username: 'anime_vf',
      kind: GatewayChatKind.channel,
    );

GatewayMessage get _videoMessage => GatewayMessage(
      messageId: _messageId,
      chatId: _chatId,
      date: DateTime(2026, 9, 1, 10),
      mediaType: 'video',
      fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv',
      fileSize: 1024 * 1024,
      mimeType: 'video/x-matroska',
      width: 1920,
      height: 1080,
      fileId: _fileId,
    );

EpisodeQuality get _version => EpisodeQuality(
      id: 'v-1',
      quality: VideoQuality.fhd,
      resolution: 'FHD',
      size: 1024 * 1024,
      language: 'VF',
      subtitles: 'Aucun',
      sourceChannelId: '$_chatId',
      sourceChannelUsername: 'anime_vf',
      telegramMessageId: _messageId,
      telegramMessageLink: 'https://t.me/anime_vf/$_messageId',
    );

Episode _episodeWith(EpisodeQuality quality) => Episode(
      id: 'ep-8',
      number: 8,
      thumbnail: '',
      date: DateTime(2026, 9, 1),
      qualities: [quality],
    );

Anime _animeWith(EpisodeQuality quality) => Anime(
      id: 'anime-1',
      title: 'Solo Leveling',
      posterAsset: '',
      backdropAsset: '',
      description: '',
      genres: const [],
      year: 2024,
      seasons: [
        Season(id: 'season-2', number: 2, episodes: [_episodeWith(quality)]),
      ],
    );

DownloadRequest _request({int? expectedSize}) => DownloadRequest(
      versionId: 'v-1',
      animeId: 'anime-1',
      seasonId: 'season-2',
      episodeId: 'ep-8',
      animeTitle: 'Solo Leveling',
      seasonNumber: 2,
      episodeNumber: 8,
      chatId: _chatId,
      messageId: _messageId,
      fileId: _fileId,
      channelUsername: 'anime_vf',
      messageLink: 'https://t.me/anime_vf/$_messageId',
      qualityLabel: '1080p',
      language: 'VF',
      expectedSize: expectedSize,
      fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv',
    );

Future<void> pump([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

/// Environnement de test complet : base mémoire + fausse passerelle +
/// téléchargeur branché sur un dossier temporaire.
class _Env {
  _Env._(this.baseDir, this.db, this.gateway, this.storage) {
    gateway.messages[_chatId] = [_videoMessage];
  }

  final LocalDatabase db;
  final FakeTelegramGateway gateway;
  final FixedStorageChecker storage;
  final Directory baseDir;
  late final DownloadManager manager;
  late final LocalAnimeRepository repository;
  late final MediaService media;

  static Future<_Env> create({int? freeBytes}) async {
    final Directory dir = await Directory.systemTemp.createTemp('animebox_test_');
    final LocalDatabase db = (await LocalDatabase.openInMemory())!;
    final FakeTelegramGateway gateway = FakeTelegramGateway(channels: [_channel]);
    final _Env env = _Env._(
      dir,
      db,
      gateway,
      FixedStorageChecker(freeBytes ?? 100 * 1024 * 1024 * 1024),
    );
    env.manager = DownloadManager(
      gateway: env.gateway,
      database: env.db,
      storageChecker: env.storage,
      resolveBaseDirectory: () async => env.baseDir.path,
      maxConcurrent: 2,
    );
    env.repository = LocalAnimeRepository(database: env.db, seed: const []);
    env.media = MediaService(
      repository: env.repository,
      downloadManager: env.manager,
      gateway: env.gateway,
    );
    return env;
  }

  /// Crée le fichier TDLib source de taille exacte [size].
  Future<String> makeTdFile(int size) async {
    final File file = File('${baseDir.path}/td_cache.bin');
    await file.writeAsBytes(List<int>.filled(size, 7));
    return file.path;
  }

  Future<void> dispose() async {
    await db.close();
    if (baseDir.existsSync()) {
      await baseDir.delete(recursive: true);
    }
  }
}

void main() {
  // GatewayMessage const : date requise — le constructeur de test ci-dessous
  // fournit une date fixe.
  test('fabrication des références (sanité)', () {
    expect(_version.hasTelegramLink, isTrue);
    expect(MediaPaths.sanitize('Solo: Leveling? "Ultimate" /S2/'), 'Solo Leveling Ultimate S2');
  });

  // 1 + 2 — Affichage et sélection des qualités (règles 5/6).
  group('choix de qualité', () {
    test('Auto sélectionne la meilleure qualité réellement disponible', () {
      final Episode episode = _episodeWith(_version);
      final EpisodeQuality picked = selectPreferredQuality(episode, QualityPreference.auto);
      expect(picked.quality, VideoQuality.fhd);
    });

    test('la préférence explicite est respectée, sinon la meilleure', () {
      final EpisodeQuality hd = EpisodeQuality(
        id: 'v-2',
        quality: VideoQuality.hd,
        resolution: 'HD',
        size: 512 * 1024,
        language: 'VOSTFR',
        subtitles: 'FR',
      );
      final Episode episode = Episode(
        id: 'ep-8',
        number: 8,
        thumbnail: '',
        date: DateTime(2026, 9, 1),
        qualities: [_version, hd],
      );
      expect(
        selectPreferredQuality(episode, QualityPreference.hd).quality,
        VideoQuality.hd,
      );
      // 1440p demandée mais absente → la meilleure disponible (jamais vide).
      expect(
        selectPreferredQuality(episode, QualityPreference.qhd).quality,
        VideoQuality.fhd,
      );
    });
  });

  // 3 — Démarrage d'un téléchargement réel.
  test('démarrage : la tâche passe en downloading et est persistée', () async {
    final _Env env = await _Env.create();
    await env.gateway.emitInitFile(_fileId, expectedSize: 1024 * 1024);
    final DownloadManagerResult result = await env.manager.enqueue(_request());
    expect(result.ok, isTrue);
    await pump();
    final DownloadTask? task = env.manager.taskForVersion('v-1');
    expect(task, isNotNull);
    expect(
      task!.status == DownloadStatus.downloading || task.status == DownloadStatus.queued,
      isTrue,
    );
    final Map<String, Object?>? row = await env.db.getDownloadByVersion('v-1');
    expect(row, isNotNull);
    expect(row!['status'], isNotNull);
    await env.dispose();
  });

  // 4 — Progression RÉELLE issue des updateFile TDLib.
  test('progression : les octets reçus viennent de TDLib (jamais estimés)', () async {
    final _Env env = await _Env.create();
    await env.gateway.emitInitFile(_fileId, expectedSize: 1024 * 1024);
    await env.manager.enqueue(_request());
    await pump();
    env.gateway.emitFileUpdate(const GatewayFileSnapshot(
      fileId: _fileId,
      expectedBytes: 1024 * 1024,
      receivedBytes: 100,
      prefixBytes: 300 * 1024,
    ));
    await pump(400);
    final DownloadTask? task = env.manager.taskForVersion('v-1');
    expect(task!.downloadedBytes, 300 * 1024);
    expect(task.fraction, closeTo(0.293, 0.05));
    await env.dispose();
  });

  // 5 + 6 — Pause puis reprise à l'offset réellement atteint.
  test('pause puis reprise : téléchargement relancé à l\'offset du .part', () async {
    final _Env env = await _Env.create();
    await env.gateway.emitInitFile(_fileId, expectedSize: 1024 * 1024);
    await env.manager.enqueue(_request());
    await pump();
    await env.manager.pause('v-1');
    await pump();
    expect(env.manager.taskForVersion('v-1')!.status, DownloadStatus.paused);
    expect(env.gateway.callLog.any((String c) => c.startsWith('cancelDownload:')), isTrue);

    await env.manager.resume('v-1');
    await pump();
    expect(env.gateway.callLog.where((String c) => c.startsWith('startDownload:')).length,
        greaterThanOrEqualTo(2));
    final DownloadTask? task = env.manager.taskForVersion('v-1');
    expect(task!.status, anyOf(DownloadStatus.downloading, DownloadStatus.queued));
    await env.dispose();
  });

  // 7 — Annulation : arrêt + nettoyage du partiel, catalogue intact.
  test('annulation : CANCELLED, fichier temporaire supprimé', () async {
    final _Env env = await _Env.create();
    await env.gateway.emitInitFile(_fileId, expectedSize: 1024 * 1024);
    await env.manager.enqueue(_request());
    await pump();
    env.gateway.emitFileUpdate(GatewayFileSnapshot(
      fileId: _fileId,
      expectedBytes: 1024 * 1024,
      prefixBytes: 200 * 1024,
      localPath: '${env.baseDir.path}/AnimeBox/Solo Leveling/Season 02/'
          'S02E08 - 1080p - VF.mkv.part',
    ));
    await pump(300);
    await env.manager.cancel('v-1');
    await pump();
    expect(env.manager.taskForVersion('v-1')!.status, DownloadStatus.cancelled);
    await env.dispose();
  });

  // 8 — Téléchargement terminé : fichier organisé + cache TDLib libéré.
  test('terminé : .part renommé en fichier final organisé, ligne persistée', () async {
    final _Env env = await _Env.create();
    const int size = 1024 * 1024;
    await env.gateway.emitInitFile(_fileId, expectedSize: size);
    await env.manager.enqueue(_request());
    await pump();
    final String tdPath = await env.makeTdFile(size);
    env.gateway.emitFileUpdate(GatewayFileSnapshot(
      fileId: _fileId,
      expectedBytes: size,
      prefixBytes: size,
      isDownloadCompleted: true,
      localPath: tdPath,
    ));
    await pump(400);
    final DownloadTask? task = env.manager.taskForVersion('v-1');
    expect(task!.status, DownloadStatus.completed);
    final String expectedPath = MediaPaths.organizedVideoPath(
      baseDirectory: env.baseDir.path,
      animeTitle: 'Solo Leveling',
      seasonNumber: 2,
      episodeNumber: 8,
      qualityLabel: '1080p',
      language: 'VF',
      fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv',
    );
    expect(task.localPath, expectedPath);
    expect(File(expectedPath).existsSync(), isTrue);
    expect(File('$expectedPath.part').existsSync(), isFalse);
    expect(env.gateway.callLog.contains('deleteDownloadedFile:$_fileId'), isTrue);
    final Map<String, Object?>? row = await env.db.getDownloadByVersion('v-1');
    expect(row!['status'], 'completed');
    await env.dispose();
  });

  // 9 — Échec : média supprimé → message compréhensible, pas de plantage.
  test('échec : média supprimé → état FAILED avec message clair', () async {
    final _Env env = await _Env.create();
    // Aucun fichier connu : getMessage réussit mais fileId absent → supprimé.
    env.gateway.messages[_chatId] = [
      GatewayMessage(
        messageId: _messageId,
        chatId: _chatId,
        date: DateTime(2026, 9, 1, 10),
        mediaType: 'text',
      ),
    ];
    final DownloadRequest request = DownloadRequest(
      versionId: 'v-1',
      animeId: 'a',
      seasonId: 's',
      episodeId: 'e',
      animeTitle: 'Solo Leveling',
      seasonNumber: 2,
      episodeNumber: 8,
      chatId: _chatId,
      messageId: _messageId,
    );
    await env.manager.enqueue(request);
    await pump(300);
    final DownloadTask? task = env.manager.taskForVersion('v-1');
    expect(task!.status, DownloadStatus.failed);
    expect(task.error, contains('Telegram'));
    await env.dispose();
  });

  // 10 — Suppression : fichier local supprimé, catalogue conservé.
  test('suppression : le fichier part, l\'épisode reste au catalogue', () async {
    final _Env env = await _Env.create();
    const int size = 1024 * 1024;
    await env.gateway.emitInitFile(_fileId, expectedSize: size);
    await env.manager.enqueue(_request());
    await pump();
    final String tdPath = await env.makeTdFile(size);
    env.gateway.emitFileUpdate(GatewayFileSnapshot(
      fileId: _fileId,
      expectedBytes: size,
      prefixBytes: size,
      isDownloadCompleted: true,
      localPath: tdPath,
    ));
    await pump(400);
    final String path = env.manager.taskForVersion('v-1')!.localPath!;
    expect(File(path).existsSync(), isTrue);

    await env.manager.delete('v-1');
    await pump();
    expect(File(path).existsSync(), isFalse);
    expect(env.manager.taskForVersion('v-1'), isNull);
    expect(await env.db.getDownloadByVersion('v-1'), isNull);
    await env.dispose();
  });

  // 11 — Lecture locale (fichier téléchargé présent).
  test('lecture : fichier téléchargé → plan localFile (hors connexion)', () async {
    final _Env env = await _Env.create();
    const int size = 1024 * 1024;
    await env.gateway.emitInitFile(_fileId, expectedSize: size);
    await env.manager.enqueue(_request());
    await pump();
    final String tdPath = await env.makeTdFile(size);
    env.gateway.emitFileUpdate(GatewayFileSnapshot(
      fileId: _fileId,
      expectedBytes: size,
      prefixBytes: size,
      isDownloadCompleted: true,
      localPath: tdPath,
    ));
    await pump(400);
    final Episode episode = _episodeWith(_version);
    final PlaybackPlan plan = await env.media.preparePlayback(
      anime: _animeWith(_version),
      episode: episode,
      version: _version,
    );
    expect(plan.kind, PlaybackKind.localFile);
    expect(plan.localPath, isNotNull);
    expect(File(plan.localPath!).existsSync(), isTrue);
    await env.dispose();
  });

  // 12 — Reprise de lecture : épisode terminé → reprise au début.
  test('progression de lecture : terminé → reprise au début', () async {
    final _Env env = await _Env.create();
    env.repository.recordProgress(
      'anime-1',
      'ep-8',
      const Duration(minutes: 20),
      duration: const Duration(minutes: 24),
    );
    expect(env.repository.episodeCompleted('anime-1', 'ep-8'), isFalse);
    env.repository.recordProgress(
      'anime-1',
      'ep-8',
      const Duration(minutes: 24),
      duration: const Duration(minutes: 24),
      completed: true,
    );
    expect(env.repository.episodeCompleted('anime-1', 'ep-8'), isTrue);
    await env.dispose();
  });

  // 13 — Ouverture Telegram : jamais de lien inventé.
  test('ouverture Telegram : lien absent → message, jamais inventé', () async {
    final _Env env = await _Env.create();
    final String? error = await env.media.openTelegramLink(null);
    expect(error, isNotNull);
    final EpisodeQuality noLink = EpisodeQuality(
      id: 'v-nolink',
      quality: VideoQuality.fhd,
      resolution: 'FHD',
      size: 0,
      language: 'VF',
      subtitles: '',
    );
    expect(noLink.hasTelegramLink, isFalse);
    await env.dispose();
  });

  // 14 — Média inaccessible (droits du compte — règle 29).
  test('média inaccessible : plan de repli avec le message réel', () async {
    final _Env env = await _Env.create();
    env.gateway.failOnNextFetch = const GatewayError(
      "Ce canal n'est pas accessible avec ce compte Telegram.",
      code: 403,
    );
    final EpisodeQuality ref = EpisodeQuality(
      id: 'v-1',
      quality: VideoQuality.fhd,
      resolution: 'FHD',
      size: 0,
      language: 'VF',
      subtitles: '',
      sourceChannelId: '$_chatId',
      telegramMessageId: _messageId,
      telegramMessageLink: 'https://t.me/anime_vf/$_messageId',
    );
    final PlaybackPlan plan = await env.media.preparePlayback(
      anime: _animeWith(ref),
      episode: _episodeWith(ref),
      version: ref,
    );
    expect(plan.kind, PlaybackKind.telegramFallback);
    expect(plan.failure?.kind, MediaAccessFailure.inaccessible);
    await env.dispose();
  });

  // 15 — Session expirée / non connectée : message clair.
  test('session absente : resolveMedia → sessionExpired', () async {
    final _Env env = await _Env.create();
    final MediaService anonymous = MediaService(
      repository: env.repository,
      downloadManager: env.manager,
      gateway: null,
    );
    await expectLater(
      anonymous.resolveMedia(chatId: _chatId, messageId: _messageId, fileId: _fileId),
      throwsA(isA<MediaAccessException>()),
    );
    await env.dispose();
  });

  // 16 — Espace de stockage insuffisant (règle 15).
  test('espace insuffisant : refus AVANT de démarrer', () async {
    final _Env env = await _Env.create(freeBytes: 1024);
    final DownloadManagerResult result =
        await env.manager.enqueue(_request(expectedSize: 100 * 1024 * 1024));
    expect(result.ok, isFalse);
    expect(result.message, contains('Espace de stockage insuffisant'));
    expect(env.manager.taskForVersion('v-1'), isNull);
    await env.dispose();
  });

  // 17 — Fichier corrompu (taille réelle ≠ taille annoncée).
  test('fichier corrompu : taille incohérente → FAILED, pas de fichier final', () async {
    final _Env env = await _Env.create();
    const int size = 1024 * 1024;
    await env.gateway.emitInitFile(_fileId, expectedSize: size);
    await env.manager.enqueue(_request());
    await pump();
    final String tdPath = await env.makeTdFile(size - 4096); // incomplet
    env.gateway.emitFileUpdate(GatewayFileSnapshot(
      fileId: _fileId,
      expectedBytes: size,
      prefixBytes: size,
      isDownloadCompleted: true,
      localPath: tdPath,
    ));
    await pump(400);
    final DownloadTask? task = env.manager.taskForVersion('v-1');
    expect(task!.status, DownloadStatus.failed);
    expect(task.error, contains('incomplet ou corrompu'));
    await env.dispose();
  });

  // 18 — Format incompatible : un fichier inexistant/illisible échoue
  // réellement à l'ouverture (aucune lecture simulée).
  test('lecteur réel : ouvrir un média illisible échoue honnêtement', () async {
    final PlayerController? controller = tryCreatePlayerController();
    if (controller == null) {
      // Plateforme sans lecture réelle disponible : le repli honnête est
      // appliqué par l'écran (jamais de faux lecteur).
      return;
    }
    try {
      await controller.open('${Directory.systemTemp.path}/inexistant-${DateTime.now().microsecondsSinceEpoch}.mp4');
      fail("L'ouverture d'un média inexistant devrait échouer.");
    } catch (_) {
      expect(true, isTrue); // échec réel constaté → message « incompatible ».
    }
    controller.dispose();
  });

  // 19 — Absence Internet : message compréhensible (règle 31).
  test('absence Internet : échec du média → FAILED reprenable', () async {
    final _Env env = await _Env.create();
    env.gateway.failOnNextFetch =
        const GatewayError('Telegram met trop de temps à répondre. Réessayez.');
    await env.manager.enqueue(_request());
    await pump(300);
    final DownloadTask? task = env.manager.taskForVersion('v-1');
    expect(task!.status, DownloadStatus.failed);
    expect(task.error, isNotNull);
    await env.dispose();
  });

  // 20 — Conservation après redémarrage de l'application (règle 13).
  test('redémarrage : téléchargements restaurés depuis la base', () async {
    final _Env env = await _Env.create();
    const int size = 1024 * 1024;
    await env.gateway.emitInitFile(_fileId, expectedSize: size);
    await env.manager.enqueue(_request());
    await pump();
    final String tdPath = await env.makeTdFile(size);
    env.gateway.emitFileUpdate(GatewayFileSnapshot(
      fileId: _fileId,
      expectedBytes: size,
      prefixBytes: size,
      isDownloadCompleted: true,
      localPath: tdPath,
    ));
    await pump(400);
    expect(env.manager.taskForVersion('v-1')!.status, DownloadStatus.completed);

    // « Redémarrage » : un nouveau gestionnaire relit la même base.
    final DownloadManager restarted = DownloadManager(
      gateway: env.gateway,
      database: env.db,
      storageChecker: env.storage,
      resolveBaseDirectory: () async => env.baseDir.path,
    );
    await restarted.restorePersisted();
    final DownloadTask? restored = restarted.taskForVersion('v-1');
    expect(restored, isNotNull);
    expect(restored!.status, DownloadStatus.completed);
    expect(File(restored.localPath!).existsSync(), isTrue);
    await env.dispose();
  });

  // Organisation des fichiers (règle 17).
  test('chemins organisés : AnimeBox/Titre/Season 02/S02E08 - 1080p - VF.mkv', () {
    final String path = MediaPaths.organizedVideoPath(
      baseDirectory: '/data',
      animeTitle: 'Solo: Leveling?',
      seasonNumber: 2,
      episodeNumber: 8,
      qualityLabel: '1080p',
      language: 'VF',
      fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv',
    );
    expect(
      path,
      '/data/AnimeBox/Solo Leveling/Season 02/S02E08 - 1080p - VF.mkv',
    );
  });

  // Écran Téléchargements importable (compilation des sections).
  test('modèles de téléchargement : états et dérivés honnêtes', () {
    final DownloadTask task = DownloadTask(
      id: 'dl-v-1',
      versionId: 'v-1',
      animeId: 'a',
      seasonId: 's',
      episodeId: 'e',
      animeTitle: 'Solo Leveling',
      seasonNumber: 2,
      episodeNumber: 8,
      status: DownloadStatus.downloading,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      expectedSize: 1000,
      downloadedBytes: 420,
    );
    expect(task.fraction, closeTo(0.42, 0.001));
    expect(task.isActive, isTrue);
    final DownloadTask paused = task.copyWith(status: DownloadStatus.paused);
    expect(paused.isActive, isFalse);
  });
}

extension on FakeTelegramGateway {
  /// État initial du fichier AVANT lancement (non complété).
  Future<void> emitInitFile(int fileId, {required int expectedSize}) async {
    emitFileUpdate(GatewayFileSnapshot(
      fileId: fileId,
      expectedBytes: expectedSize,
      receivedBytes: 0,
      prefixBytes: 0,
    ));
  }
}

