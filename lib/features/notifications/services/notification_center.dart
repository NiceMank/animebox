import '../../local/data/local_database.dart';
import '../../media/models/download_models.dart';
import '../models/notification_models.dart';
import 'notification_service.dart';
import 'notification_settings.dart';

/// Centre de notifications (prompt 9).
///
/// Responsabilités :
/// - transformer un [SyncRunSummary] RÉEL en notifications « nouvel
///   épisode » (règle 4), en regroupant les qualités d'un même épisode
///   en UNE notification (règle 5) et sans jamais notifier deux fois le
///   même épisode (règle 6) ;
/// - relayer les événements RÉELS du [DownloadManager] (règles 8 à 10) :
///   progression (uniquement les valeurs mesurées par TDLib), terminé,
///   interrompu ;
/// - appliquer les préférences : source (règle 17), animé (règle 18),
///   mode silencieux (règle 19), heures silencieuses (règle 20) ;
/// - router les clics : Anime → Saison → Épisode (règle 7), « Lire »,
///   « Reprendre ».
///
/// Une notification n'est créée QUE pour un contenu réellement détecté
/// (règle 32) — jamais de fausse notification.
class NotificationCenter {
  NotificationCenter({
    required NotificationService notifications,
    required NotificationSettings settings,
    LocalDatabase? database,
    DateTime Function()? now,
  })  : // ignore: prefer_initializing_formals
        _notifications = notifications,
        // ignore: prefer_initializing_formals
        _settings = settings,
        // ignore: prefer_initializing_formals
        _database = database,
        _now = now ?? DateTime.now;

  final NotificationService _notifications;
  final NotificationSettings _settings;
  final LocalDatabase? _database;
  final DateTime Function() _now;

  /// Navigation branchée par l'application : ouvrir l'épisode (anime →
  /// saison → épisode) — règle 7.
  void Function(String animeId, String seasonId, String episodeId)? onOpenEpisode;

  /// « Lire » un téléchargement terminé (règle 9).
  void Function(String animeId, String episodeId)? onPlayDownload;

  /// « Reprendre » un téléchargement interrompu (règle 10).
  Future<void> Function(String versionId)? onResumeDownload;

  /// Cache des épisodes déjà notifiés (persistance : base locale).
  Map<String, int>? _notifiedQualityCounts;
  bool _cacheLoading = false;

  /// Anti-spam de progression (règle 8) : dernière mise à jour par
  /// téléchargement.
  final Map<String, DateTime> _lastProgressAt = <String, DateTime>{};

  static const Duration _progressMinInterval = Duration(seconds: 4);

  // --------------------------------------------------------------------
  // 4/5/6. Nouveaux épisodes — détection, regroupement, doublons
  // --------------------------------------------------------------------

  /// Point d'entrée après une synchronisation RÉELLE (manuelle ou
  /// automatique). Ne fait rien quand aucun épisode n'a été touché.
  Future<void> handleSyncSummary(SyncRunSummary summary) async {
    if (summary.episodes.isEmpty) return;
    if (!_settings.newEpisodesEnabled) return;
    await _ensureCache();
    final bool silent = _settings.shouldDeliverSilently(_now());

    for (final SyncRunEpisode episode in summary.episodes) {
      // Préférences par source (règle 17) et par animé (règle 18).
      if (!await _settings.isSourceNotificationsEnabled(episode.sourceId)) {
        continue;
      }
      if (!await _settings.isAnimeNotificationsEnabled(episode.animeId)) {
        continue;
      }

      final int? alreadyNotified = _notifiedQualityCounts?[episode.episodeId];
      if (alreadyNotified != null && episode.totalQualities <= alreadyNotified) {
        continue; // règle 6 : déjà signalé, rien de neuf à dire
      }

      final bool isUpdate = alreadyNotified != null;
      final String qualities = episode.totalQualities > 1
          ? '${episode.totalQualities} qualités disponibles'
          : <String>[
              if (episode.qualityLabel != null) episode.qualityLabel!,
              if (episode.language != null) episode.language!,
            ].join(' ');
      final String detail = '${episode.seasonEpisodeLabel}${qualities.isEmpty ? '' : ' • $qualities'}';

      await _notifications.show(ShownNotification(
        id: episodeNotificationId(episode.episodeId),
        channel: silent
            ? AppNotificationChannel.newEpisodesSilent
            : AppNotificationChannel.newEpisodes,
        title: isUpdate ? 'Nouvelle qualité disponible' : 'Nouvel épisode disponible',
        body: '${episode.animeTitle}\n$detail'.trim(),
        payload: AnimeBoxNotificationPayload(
          type: NotificationPayloadType.episode,
          animeId: episode.animeId,
          seasonId: episode.seasonId,
          episodeId: episode.episodeId,
        ).encode(),
      ));

      _notifiedQualityCounts?[episode.episodeId] = episode.totalQualities;
      await _persistNotified(episode);
    }
  }

  Future<void> _ensureCache() async {
    if (_notifiedQualityCounts != null || _cacheLoading) return;
    _cacheLoading = true;
    try {
      final LocalDatabase? db = _database;
      _notifiedQualityCounts =
          db == null ? <String, int>{} : await db.loadNotifiedQualityCounts();
    } catch (_) {
      _notifiedQualityCounts ??= <String, int>{};
    } finally {
      _cacheLoading = false;
    }
  }

  Future<void> _persistNotified(SyncRunEpisode episode) async {
    final LocalDatabase? db = _database;
    if (db == null) return;
    try {
      await db.markEpisodeNotified(
        episode.episodeId,
        animeId: episode.animeId,
        animeTitle: episode.animeTitle,
        seasonNumber: episode.seasonNumber,
        episodeNumber: episode.episodeNumber,
        qualityCount: episode.totalQualities,
        notifiedAt: _now(),
      );
    } catch (_) {
      // La persistance échoue : le cache mémoire évite déjà les doublons
      // pour cette session.
    }
  }

  // --------------------------------------------------------------------
  // 8/9/10. Téléchargements — progression, terminé, interrompu
  // --------------------------------------------------------------------

  /// Relaie un événement RÉEL du [DownloadManager] (règles 8 à 10).
  /// Jamais de fausse progression : seules les valeurs mesurées par
  /// TDLib sont affichées.
  Future<void> handleDownloadEvent(DownloadEvent event) async {
    if (!_settings.downloadNotificationsEnabled) return;
    final DownloadTask task = event.task;
    final int id = downloadNotificationId(task.versionId);

    switch (event.kind) {
      case DownloadEventKind.started:
      case DownloadEventKind.resumed:
        break; // la première progression réelle ouvrira la notification
      case DownloadEventKind.progress:
        if (!_settings.downloadProgressEnabled) return;
        final int? total = task.expectedSize;
        if (total == null || total <= 0) return;
        final DateTime now = _now();
        final DateTime? last = _lastProgressAt[task.versionId];
        if (last != null && now.difference(last) < _progressMinInterval) return;
        _lastProgressAt[task.versionId] = now;
        await _notifications.show(ShownNotification(
          id: id,
          channel: AppNotificationChannel.downloads,
          title: 'Téléchargement en cours',
          body: task.animeTitle,
          ongoing: true,
          progress: task.downloadedBytes,
          progressMax: total,
          onlyAlertOnce: true,
        ));
      case DownloadEventKind.paused:
      case DownloadEventKind.cancelled:
      case DownloadEventKind.deleted:
        _lastProgressAt.remove(task.versionId);
        await _notifications.cancel(id);
      case DownloadEventKind.completed:
        _lastProgressAt.remove(task.versionId);
        // Règle 9 : seulement quand le gestionnaire a VÉRIFIÉ le fichier.
        if (task.status != DownloadStatus.completed) return;
        await _notifications.show(ShownNotification(
          id: id,
          channel: AppNotificationChannel.downloads,
          title: 'Téléchargement terminé',
          body: _downloadSubtitle(task),
          actions: const <NotificationActionButton>[
            NotificationActionButton(id: NotificationActions.play, label: 'Lire'),
          ],
          payload: AnimeBoxNotificationPayload(
            type: NotificationPayloadType.downloadCompleted,
            animeId: task.animeId,
            seasonId: task.seasonId,
            episodeId: task.episodeId,
            versionId: task.versionId,
          ).encode(),
        ));
      case DownloadEventKind.failed:
        _lastProgressAt.remove(task.versionId);
        // Jamais « terminé » sur un échec (règle 10).
        if (task.status == DownloadStatus.completed) return;
        await _notifications.show(ShownNotification(
          id: id,
          channel: AppNotificationChannel.downloads,
          title: 'Téléchargement interrompu',
          body: _downloadSubtitle(task, includeError: true),
          actions: <NotificationActionButton>[
            if (task.resumable)
              const NotificationActionButton(id: NotificationActions.resume, label: 'Reprendre'),
          ],
          payload: AnimeBoxNotificationPayload(
            type: NotificationPayloadType.downloadFailed,
            animeId: task.animeId,
            seasonId: task.seasonId,
            episodeId: task.episodeId,
            versionId: task.versionId,
          ).encode(),
        ));
    }
  }

  String _downloadSubtitle(DownloadTask task, {bool includeError = false}) {
    final String episode = 'S${task.seasonNumber.toString().padLeft(2, '0')}'
        'E${task.episodeNumber.toString().padLeft(2, '0')}';
    final List<String> parts = <String>[
      episode,
      if (task.qualityLabel != null) task.qualityLabel!,
      if (includeError && task.error != null) task.error!,
    ];
    return '${task.animeTitle}\n${parts.join(' • ')}'.trim();
  }

  // --------------------------------------------------------------------
  // 7. Clic sur une notification — ouvrir le BON écran
  // --------------------------------------------------------------------

  /// Gère un clic (corps ou action). La charge utile est décodée avec
  /// tolérance : un clic illisible ne plante jamais l'application.
  Future<void> handleNotificationTap(String? actionId, String? payload) async {
    final AnimeBoxNotificationPayload? data = AnimeBoxNotificationPayload.decode(payload);
    if (data == null) return;
    switch (data.type) {
      case NotificationPayloadType.episode:
        final String? animeId = data.animeId;
        final String? seasonId = data.seasonId;
        final String? episodeId = data.episodeId;
        if (animeId != null && seasonId != null && episodeId != null) {
          onOpenEpisode?.call(animeId, seasonId, episodeId);
        }
      case NotificationPayloadType.downloadCompleted:
        final String? animeId = data.animeId;
        final String? episodeId = data.episodeId;
        if (animeId != null && episodeId != null) {
          // « Lire » (action) ou clic corps : ouvrir la lecture directement.
          onPlayDownload?.call(animeId, episodeId);
        }
      case NotificationPayloadType.downloadFailed:
        if (actionId == NotificationActions.resume) {
          final String? versionId = data.versionId;
          if (versionId != null && onResumeDownload != null) {
            await onResumeDownload!(versionId);
            return;
          }
        }
        final String? animeId = data.animeId;
        final String? seasonId = data.seasonId;
        final String? episodeId = data.episodeId;
        if (animeId != null && seasonId != null && episodeId != null) {
          onOpenEpisode?.call(animeId, seasonId, episodeId);
        }
    }
  }
}
