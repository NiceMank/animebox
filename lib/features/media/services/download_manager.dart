import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../local/data/local_database.dart';
import '../../telegram/data/gateway/telegram_gateway.dart';
import '../models/download_models.dart';
import 'media_paths.dart';
import 'storage_checker.dart';

/// Résultat d'une demande de téléchargement (message compréhensible).
class DownloadManagerResult {
  const DownloadManagerResult(this.ok, [this.message]);

  const DownloadManagerResult.failure(this.message)
      : ok = false,
        super();

  final bool ok;
  final String? message;
}

/// Téléchargement RÉEL d'un média Telegram via TDLib (prompt 8).
///
/// - progression : événements `updateFile` de TDLib — jamais estimée ;
/// - reprise : TDLib conserve le fichier partiel, `downloadFile` est
///   relancé à l'offset atteint (multiple de 1024 exigé) ;
/// - fichier partiel : `<cible>.part` pendant toute la durée, renommé
///   uniquement après vérification de la taille réelle (règle 14) ;
/// - file d'attente : [maxConcurrent] téléchargements simultanés au plus ;
/// - persistance : table `downloads` de la base locale — les tâches
///   survivent au redémarrage (règle 13) ;
/// - aucune donnée ne transite par un serveur intermédiaire (règle 40).
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.gateway,
    required this.database,
    required this.storageChecker,
    required this._resolveBaseDirectory,
    this.maxConcurrent = 2,
    this.onEvent,
  });

  /// Granularité TDLib (multiple de 1024 exigé pour les offsets).
  static const int _chunkAlign = 1024;

  /// Marge de sécurité au-dessus de la taille à télécharger (2 %).
  static const double _freeSpaceMargin = 1.02;

  /// Sans nouvelle d'un téléchargement pendant ce délai → interrompu.
  static const Duration _inactivityTimeout = Duration(seconds: 90);

  /// Passerelle TDLib — null en démonstration (aucun téléchargement
  /// réel possible : l'interface affiche un message honnête).
  final TelegramGateway? gateway;
  final LocalDatabase? database;
  final StorageChecker storageChecker;
  final Future<String?> Function() _resolveBaseDirectory;
  final int maxConcurrent;

  /// Sortie d'événements (notifications du prompt 9 — branchée par
  /// l'application au démarrage).
  void Function(DownloadEvent)? onEvent;

  final Map<String, DownloadTask> _tasks = <String, DownloadTask>{};
  final Set<String> _active = <String>{};
  final Set<String> _interruptRequested = <String>{};
  final Map<String, Completer<void>> _interrupts = <String, Completer<void>>{};
  bool _stopped = false;
  bool _pumpScheduled = false;

  /// Tâches connues (toutes sections de l'écran Téléchargements).
  List<DownloadTask> get tasks => List.of(_tasks.values)
    ..sort((DownloadTask a, DownloadTask b) => b.updatedAt.compareTo(a.updatedAt));

  DownloadTask? taskForVersion(String versionId) => _tasks[versionId];

  DownloadTask? taskById(String id) {
    for (final DownloadTask task in _tasks.values) {
      if (task.id == id) return task;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Chargement persistant (redémarrage de l'application — règles 13/20)
  // -------------------------------------------------------------------------

  /// Recharge l'état persisté : les téléchargements terminés sont vérifiés
  /// (fichier réellement présent), les autres passent en pause —
  /// « Téléchargement interrompu » affiché avec [resume] possible.
  Future<void> restorePersisted() async {
    final LocalDatabase? db = database;
    if (db == null) return;
    try {
      final List<Map<String, Object?>> rows = await db.listDownloads();
      final String? base = await _resolveBaseDirectory();
      for (final Map<String, Object?> row in rows) {
        final DownloadTask task = _taskFromRow(row);
        if (task.status == DownloadStatus.completed) {
          final bool present = task.localPath != null && File(task.localPath!).existsSync();
          _tasks[task.versionId] = present
              ? task
              : task.copyWith(
                  status: DownloadStatus.failed,
                  error: 'Fichier introuvable sur l\'appareil.',
                  resumable: false,
                );
          continue;
        }
        // Non terminé : le téléchargement reprendra à la taille du .part.
        _tasks[task.versionId] = task.copyWith(
          status: DownloadStatus.paused,
          resumable: base != null && _partPathFor(task, base) != null,
        );
      }
      notifyListeners();
    } catch (_) {
      // Base indisponible : aucune tâche restaurée, sans plantage.
    }
  }

  DownloadTask _taskFromRow(Map<String, Object?> row) {
    return DownloadTask(
      id: row['id']! as String,
      versionId: row['version_id']! as String,
      animeId: row['anime_id']! as String,
      seasonId: row['season_id']! as String,
      episodeId: row['episode_id']! as String,
      animeTitle: (row['anime_title']?.toString().isNotEmpty ?? false)
          ? row['anime_title']! as String
          : 'Anime',
      seasonNumber: (row['season_number'] as num?)?.toInt() ?? 1,
      episodeNumber: (row['episode_number'] as num?)?.toInt() ?? 0,
      status: DownloadStatus.values.firstWhere(
        (DownloadStatus s) => s.name == row['status'],
        orElse: () => DownloadStatus.failed,
      ),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now(),
      chatId: (row['chat_id'] as num?)?.toInt(),
      messageId: (row['message_id'] as num?)?.toInt(),
      fileId: (row['file_id'] as num?)?.toInt(),
      channelUsername: row['channel_username']?.toString(),
      messageLink: row['message_link']?.toString(),
      qualityLabel: row['quality']?.toString(),
      language: row['language']?.toString(),
      expectedSize: (row['total_bytes'] as num?)?.toInt(),
      downloadedBytes: (row['downloaded_bytes'] as num?)?.toInt() ?? 0,
      localPath: row['local_path']?.toString(),
      fileName: row['file_name']?.toString(),
      error: row['error']?.toString(),
      resumable: (row['resumable'] as num?)?.toInt() == 1,
    );
  }

  Future<void> _persist(DownloadTask task) async {
    final LocalDatabase? db = database;
    if (db == null) return;
    try {
      await db.upsertDownload(<String, Object?>{
        'id': task.id,
        'version_id': task.versionId,
        'anime_id': task.animeId,
        'season_id': task.seasonId,
        'episode_id': task.episodeId,
        'chat_id': task.chatId,
        'message_id': task.messageId,
        'file_id': task.fileId,
        'quality': task.qualityLabel,
        'language': task.language,
        'anime_title': task.animeTitle,
        'season_number': task.seasonNumber,
        'episode_number': task.episodeNumber,
        'message_link': task.messageLink,
        'status': task.status.name,
        'total_bytes': task.expectedSize,
        'downloaded_bytes': task.downloadedBytes,
        'local_path': task.localPath,
        'file_name': task.fileName,
        'error': task.error,
        'resumable': task.resumable ? 1 : 0,
        'created_at': task.createdAt.toIso8601String(),
        'updated_at': task.updatedAt.toIso8601String(),
      });
    } catch (_) {
      // Persistance impossible : l'état mémoire reste fiable.
    }
  }

  // -------------------------------------------------------------------------
  // File d'attente
  // -------------------------------------------------------------------------

  /// Met un téléchargement en file (règles 8/15/16). Refus propre si :
  /// version déjà en file, référence Telegram manquante, espace insuffisant.
  Future<DownloadManagerResult> enqueue(DownloadRequest request) async {
    if (_stopped) {
      return const DownloadManagerResult.failure(
        'L\'application est en cours d\'arrêt : réessayez au prochain lancement.',
      );
    }
    if (!request.hasTelegramReference) {
      return const DownloadManagerResult.failure(
        'Aucune référence Telegram exploitable pour cette version.',
      );
    }
    final DownloadTask? existing = _tasks[request.versionId];
    if (existing != null && (existing.isActive || existing.isBusy)) {
      return const DownloadManagerResult.failure('Ce téléchargement est déjà en cours.');
    }
    if (existing != null && existing.status == DownloadStatus.completed) {
      return const DownloadManagerResult.failure('Cet épisode est déjà téléchargé.');
    }

    // Vérification de l'espace disponible (règle 15) — uniquement quand la
    // taille ET l'espace sont mesurables (jamais de valeur inventée).
    final int? expected = request.expectedSize;
    if (expected != null && expected > 0) {
      final String? base = await _resolveBaseDirectory();
      final int? free = await storageChecker.freeBytes(base);
      if (free != null && free < expected * _freeSpaceMargin) {
        return DownloadManagerResult.failure(
          'Espace de stockage insuffisant. Taille vidéo : ${_formatBytes(expected)}, '
          'espace disponible : ${_formatBytes(free)}.',
        );
      }
    }

    final DateTime now = DateTime.now();
    final DownloadTask task = DownloadTask(
      id: 'dl-${request.versionId}',
      versionId: request.versionId,
      animeId: request.animeId,
      seasonId: request.seasonId,
      episodeId: request.episodeId,
      animeTitle: request.animeTitle,
      seasonNumber: request.seasonNumber,
      episodeNumber: request.episodeNumber,
      status: DownloadStatus.queued,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      chatId: request.chatId,
      messageId: request.messageId,
      fileId: request.fileId,
      channelUsername: request.channelUsername,
      messageLink: request.messageLink,
      qualityLabel: request.qualityLabel,
      language: request.language,
      expectedSize: request.expectedSize,
      downloadedBytes: 0,
      fileName: request.fileName,
    );
    _tasks[task.versionId] = task;
    await _persist(task);
    _emit(DownloadEventKind.started, task);
    notifyListeners();
    _pump();
    return const DownloadManagerResult(true, 'Téléchargement ajouté à la file.');
  }

  /// Lance les tâches en file dans la limite de simultanéité (règle 9).
  void _pump() {
    if (_pumpScheduled || _stopped) return;
    _pumpScheduled = true;
    scheduleMicrotask(() async {
      _pumpScheduled = false;
      while (!_stopped && _active.length < maxConcurrent) {
        final DownloadTask? next = _tasks.values
            .where((DownloadTask t) => t.status == DownloadStatus.queued && !_active.contains(t.versionId))
            .fold<DownloadTask?>(null, (DownloadTask? best, DownloadTask t) =>
                best == null || t.updatedAt.isBefore(best.updatedAt) ? t : best);
        if (next == null) return;
        _active.add(next.versionId);
        unawaited(_runTask(next));
      }
    });
  }

  // -------------------------------------------------------------------------
  // Exécution d'une tâche
  // -------------------------------------------------------------------------

  Future<void> _runTask(DownloadTask initial) async {
    // Mise en pause demandée avant le démarrage effectif : ne pas lancer.
    if (_interruptRequested.contains(initial.versionId)) {
      _interruptRequested.remove(initial.versionId);
      _update(
        initial.copyWith(status: DownloadStatus.paused, resumable: true),
        persist: true,
        event: DownloadEventKind.paused,
      );
      _active.remove(initial.versionId);
      _pump();
      return;
    }
    DownloadTask task = initial.copyWith(status: DownloadStatus.downloading, clearError: true);
    _update(task, persist: true);

    StreamSubscription<GatewayFileSnapshot>? sub;
    Timer? inactivity;
    try {
      if (gateway == null) {
        throw const _Permanent('Connectez-vous à Telegram pour télécharger.');
      }
      final String? base = await _resolveBaseDirectory();
      if (base == null) {
        throw const _Interrupted('Stockage indisponible sur cet appareil.');
      }
      final int? chatId = task.chatId;
      if (chatId == null || task.messageId == null) {
        throw const _Permanent('Aucune référence Telegram exploitable pour cette version.');
      }

      // 1. Résolution du fichier (fileId réel — jamais inventé).
      int fileId = task.fileId ?? 0;
      int? expected = task.expectedSize;
      String? tdRemotePath;
      if (fileId <= 0) {
        final GatewayMessage message =
            await gateway!.getMessage(chatId: chatId, messageId: task.messageId!);
        fileId = message.fileId ?? 0;
        expected = message.fileSize ?? expected;
        if (fileId <= 0) {
          throw const _Permanent('Ce média n\'est plus disponible sur Telegram.');
        }
        task = task.copyWith(fileId: fileId, expectedSize: expected);
      }

      // 2. État TDLib actuel (cache éventuel, taille mesurée).
      final GatewayFileSnapshot snapshot = await gateway!.getFileSnapshot(fileId);
      expected = snapshot.expectedBytes ?? expected;
      if (snapshot.expectedBytes != null) task = task.copyWith(expectedSize: snapshot.expectedBytes);

      final String targetPath = MediaPaths.organizedVideoPath(
        baseDirectory: base,
        animeTitle: task.animeTitle,
        seasonNumber: task.seasonNumber,
        episodeNumber: task.episodeNumber,
        qualityLabel: task.qualityLabel,
        language: task.language,
        fileName: task.fileName,
      );
      final String partPath = '$targetPath.part';
      final Directory targetDir = File(targetPath).parent;

      // 3. Déjà présent en cache TDLib COMPLET → copie directe.
      if (snapshot.isDownloadCompleted && snapshot.localPath != null) {
        await _finalize(
          task: task,
          tdPath: snapshot.localPath!,
          partPath: partPath,
          targetPath: targetPath,
          expectedBytes: expected,
        );
        return;
      }

      // 4. Reprise : taille du .part arrondie au multiple de 1024.
      int offset = 0;
      final File part = File(partPath);
      if (await part.exists()) {
        final int length = await part.length();
        offset = (length ~/ _chunkAlign) * _chunkAlign;
      }

      // 5. Espace disponible (vérifié à chaque (re)démarrage — règle 15).
      if (expected != null) {
        final int? free = await storageChecker.freeBytes(base);
        if (free != null && free < (expected - offset) * _freeSpaceMargin) {
          throw _Permanent(
            'Espace de stockage insuffisant. Taille vidéo : ${_formatBytes(expected)}, '
            'espace disponible : ${_formatBytes(free)}.',
          );
        }
      }

      await targetDir.create(recursive: true);

      // 6. Progression : abonnement AVANT le lancement (aucun événement perdu).
      final Completer<GatewayFileSnapshot> done = Completer<GatewayFileSnapshot>();
      final Completer<void> interrupt = Completer<void>();
      _interrupts[task.versionId] = interrupt;
      DateTime lastUpdateAt = DateTime.now();
      DateTime lastNotifyAt = DateTime.now();
      DateTime lastPersistAt = DateTime.now();
      int lastBytes = offset;
      DateTime lastBytesAt = lastUpdateAt;
      double? speed;
      sub = gateway!.fileUpdates.listen((GatewayFileSnapshot update) {
        if (update.fileId != fileId) return;
        lastUpdateAt = DateTime.now();
        if (update.isDownloadCompleted && update.localPath != null && !done.isCompleted) {
          done.complete(update);
          return;
        }
        final int received = (update.prefixBytes > 0 ? update.prefixBytes : update.receivedBytes) + offset;
        final DateTime now = DateTime.now();
        final Duration dt = now.difference(lastBytesAt);
        if (dt.inMilliseconds >= 800 && received > lastBytes) {
          speed = (received - lastBytes) / (dt.inMicroseconds / 1e6);
          lastBytes = received;
          lastBytesAt = now;
        }
        final bool shouldNotify = now.difference(lastNotifyAt).inMilliseconds >= 400;
        final bool shouldPersist = now.difference(lastPersistAt).inMilliseconds >= 2500;
        task = task.copyWith(
          downloadedBytes: received,
          expectedSize: update.expectedBytes ?? task.expectedSize,
        );
        if (shouldNotify || shouldPersist) {
          final Duration? eta = (speed != null && speed! > 0 && expected != null)
              ? Duration(seconds: ((expected - received) / speed!).round())
              : null;
          _update(task.copyWith(downloadedBytes: received, speedBytesPerSec: speed, eta: eta),
              persist: shouldPersist, event: DownloadEventKind.progress);
          if (shouldNotify) lastNotifyAt = now;
          if (shouldPersist) lastPersistAt = now;
        }
      });
      inactivity = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
        if (DateTime.now().difference(lastUpdateAt) > _inactivityTimeout && !done.isCompleted) {
          done.completeError(const _Interrupted('Téléchargement interrompu (plus de nouvelles).'));
        }
      });

      // 7. Lancement TDLib (à l'offset de reprise).
      await gateway!.startDownload(fileId: fileId, offset: offset, limit: 0, priority: true);

      // 8. Attente de la complétion RÉELLE (ou interruption immédiate).
      final GatewayFileSnapshot finalSnapshot =
          await Future.any(<Future<GatewayFileSnapshot>>[
        done.future,
        interrupt.future.then<GatewayFileSnapshot>(
          (_) => throw const _Interrupted('Interrompu à la demande.'),
        ),
      ]);
      _interruptRequested.remove(task.versionId);
      await _finalize(
        task: task,
        tdPath: finalSnapshot.localPath!,
        partPath: partPath,
        targetPath: targetPath,
        expectedBytes: expected,
      );
    } on _Permanent catch (error) {
      _interruptRequested.remove(task.versionId);
      task = task.copyWith(
        status: DownloadStatus.failed,
        error: error.message,
        resumable: false,
        speedBytesPerSec: null,
        eta: null,
      );
      _update(task, persist: true, event: DownloadEventKind.failed);
    } on _Interrupted catch (error) {
      final bool userPause = _interruptRequested.remove(task.versionId) || _stopped;
      await _safeCancelDownload(task);
      // Une annulation déjà enregistrée prime (jamais d'écrasement).
      final DownloadTask? current = _tasks[task.versionId];
      if (current?.status == DownloadStatus.cancelled) {
        task = current!;
      } else if (userPause) {
        // Pause utilisateur : état PAUSED, reprise possible (règle 11).
        task = task.copyWith(status: DownloadStatus.paused, resumable: true, speedBytesPerSec: null, eta: null);
      } else {
        // Interruption réseau/app : « Téléchargement interrompu »,
        // reprise possible — règle 13.
        task = task.copyWith(
          status: DownloadStatus.paused,
          error: error.message,
          resumable: true,
          speedBytesPerSec: null,
          eta: null,
        );
      }
      _update(task, persist: true, event: userPause ? DownloadEventKind.paused : DownloadEventKind.failed);
    } on GatewayError catch (error) {
      _interruptRequested.remove(task.versionId);
      await _safeCancelDownload(task);
      task = task.copyWith(
        status: DownloadStatus.failed,
        error: error.message,
        resumable: true,
        speedBytesPerSec: null,
        eta: null,
      );
      _update(task, persist: true, event: DownloadEventKind.failed);
    } catch (_) {
      _interruptRequested.remove(task.versionId);
      await _safeCancelDownload(task);
      task = task.copyWith(
        status: DownloadStatus.failed,
        error: 'Le téléchargement a échoué. Réessayez.',
        resumable: true,
      );
      _update(task, persist: true, event: DownloadEventKind.failed);
    } finally {
      inactivity?.cancel();
      await sub?.cancel();
      _active.remove(task.versionId);
      notifyListeners();
      if (!_stopped) _pump();
    }
  }

  /// Fichier TDLib complet → copie vers `<cible>.part` → vérification de
  /// taille → renommage final (règle 14 : jamais de partiel « terminé »).
  Future<void> _finalize({
    required DownloadTask task,
    required String tdPath,
    required String partPath,
    required String targetPath,
    required int? expectedBytes,
  }) async {
    final File source = File(tdPath);
    if (!await source.exists()) {
      throw const _Interrupted('Le fichier source a disparu avant la fin de la copie.');
    }
    await File(targetPath).parent.create(recursive: true);
    final File part = File(partPath);
    await source.openRead(0).pipe(part.openWrite());
    final int actual = await part.length();
    // Vérification RÉELLE : taille mesurée vs taille annoncée (si connue).
    if (expectedBytes != null && actual != expectedBytes) {
      await part.delete().catchError((_) => part);
      throw _Permanent(
        'Le fichier téléchargé est incomplet ou corrompu ($actual / $expectedBytes octets).',
      );
    }
    await part.rename(targetPath);
    // Libération du cache TDLib (la copie organisée est désormais la référence).
    if (task.fileId != null) {
      await gateway?.deleteDownloadedFile(fileId: task.fileId!);
    }
    final DownloadTask finished = task.copyWith(
      status: DownloadStatus.completed,
      downloadedBytes: actual,
      localPath: targetPath,
      resumable: false,
      speedBytesPerSec: null,
      eta: null,
      clearError: true,
    );
    _update(finished, persist: true, event: DownloadEventKind.completed);
  }

  // -------------------------------------------------------------------------
  // Actions utilisateur (règles 11/12/19/20)
  // -------------------------------------------------------------------------

  /// [ Pause ] — arrête proprement TDLib ; le `.part` est conservé.
  Future<void> pause(String versionId) async {
    final DownloadTask? task = _tasks[versionId];
    if (task == null || !task.isBusy && task.status != DownloadStatus.queued) return;
    _interruptRequested.add(versionId);
    _interrupts[versionId]?.complete();
    await _safeCancelDownload(task);
    // L'état PAUSED est posé par la boucle d'exécution (réaction à
    // l'interruption demandée) — on ne l'invente pas ici prématurément.
  }

  /// [ Reprendre ] — file d'attente (reprise à l'offset du `.part`).
  Future<void> resume(String versionId) async {
    final DownloadTask? task = _tasks[versionId];
    if (task == null) return;
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed &&
        task.status != DownloadStatus.cancelled) {
      return;
    }
    if (!task.resumable) return;
    _tasks[versionId] = task.copyWith(
      status: DownloadStatus.queued,
      clearError: true,
    );
    _update(_tasks[versionId]!, persist: true, event: DownloadEventKind.resumed);
    _pump();
  }

  /// [ Annuler ] (après confirmation côté UI) — arrêt, suppression du
  /// fichier temporaire, état CANCELLED. Le catalogue n'est pas touché.
  Future<void> cancel(String versionId) async {
    final DownloadTask? task = _tasks[versionId];
    if (task == null) return;
    _interruptRequested.add(versionId);
    await _safeCancelDownload(task);
    final String? base = await _resolveBaseDirectory();
    final String? partPath = base == null ? null : _partPathFor(task, base);
    if (partPath != null) {
      final File part = File(partPath);
      if (await part.exists()) {
        await part.delete().catchError((_) => part);
      }
    }
    // La boucle d'exécution (si active) respecte l'état CANCELLED posé ici.
    _tasks[versionId] = task.copyWith(
      status: DownloadStatus.cancelled,
      error: 'Téléchargement annulé.',
      downloadedBytes: 0,
      resumable: false,
      speedBytesPerSec: null,
      eta: null,
    );
    await _persist(_tasks[versionId]!);
    _emit(DownloadEventKind.cancelled, _tasks[versionId]!);
    notifyListeners();
  }

  /// [ Supprimer ] — supprime le fichier local ET la ligne de suivi ;
  /// anime/saison/épisode/version/références Telegram restent intacts
  /// (règle 20).
  Future<void> delete(String versionId) async {
    final DownloadTask? task = _tasks[versionId];
    if (task == null) return;
    if (task.isBusy) {
      await cancel(versionId);
    }
    final String? path = task.localPath;
    if (path != null) {
      final File file = File(path);
      if (await file.exists()) {
        await file.delete().catchError((_) => file);
      }
    }
    _tasks.remove(versionId);
    final LocalDatabase? db = database;
    if (db != null) {
      try {
        await db.deleteDownload(task.id);
      } catch (_) {}
    }
    _emit(DownloadEventKind.deleted, task);
    notifyListeners();
  }

  /// Arrêt propre de tout (fermeture de l'app) — rien n'est perdu :
  /// les `.part` et l'état persisté permettent la reprise (règle 13).
  Future<void> stopAll() async {
    _stopped = true;
    for (final String versionId in List.of(_active)) {
      _interruptRequested.add(versionId);
      _interrupts[versionId]?.complete();
      await _safeCancelDownload(_tasks[versionId] ?? taskById('dl-$versionId'));
    }
    for (final DownloadTask task in _tasks.values) {
      if (task.isBusy || task.status == DownloadStatus.queued) {
        _tasks[task.versionId] = task.copyWith(status: DownloadStatus.paused, resumable: true);
        await _persist(_tasks[task.versionId]!);
      }
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Utilitaires
  // -------------------------------------------------------------------------

  void _update(DownloadTask task, {bool persist = false, DownloadEventKind? event}) {
    _tasks[task.versionId] = task;
    if (persist) unawaited(_persist(task));
    if (event != null) _emit(event, task);
    notifyListeners();
  }

  void _emit(DownloadEventKind kind, DownloadTask task) {
    try {
      onEvent?.call(DownloadEvent(kind, task));
    } catch (_) {
      // Un récepteur d'événements défaillant ne casse jamais un téléchargement.
    }
  }

  Future<void> _safeCancelDownload(DownloadTask? task) async {
    final int? fileId = task?.fileId;
    if (fileId == null || fileId <= 0) return;
    try {
      await gateway?.cancelDownload(fileId: fileId);
    } catch (_) {
      // Déjà terminé/annulé côté TDLib.
    }
  }

  /// Chemin du `.part` reconstruit à l'identique (reprise après redémarrage).
  String? _partPathFor(DownloadTask task, String base) {
    final String target = MediaPaths.organizedVideoPath(
      baseDirectory: base,
      animeTitle: task.animeTitle,
      seasonNumber: task.seasonNumber,
      episodeNumber: task.episodeNumber,
      qualityLabel: task.qualityLabel,
      language: task.language,
      fileName: task.fileName,
    );
    return '$target.part';
  }

  static String _formatBytes(int bytes) {
    const int mb = 1024 * 1024;
    const int gb = mb * 1024;
    if (bytes >= gb) {
      final double value = bytes / gb;
      return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} Go';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).round()} Mo';
    }
    return '$bytes o';
  }
}

/// Erreur permanente : reprise impossible (référence absente, média
/// supprimé, espace insuffisant, fichier corrompu).
class _Permanent implements Exception {
  const _Permanent(this.message);
  final String message;
}

/// Interruption récupérable : le `.part` permet une reprise à l'offset.
class _Interrupted implements Exception {
  const _Interrupted(this.message);
  final String message;
}
