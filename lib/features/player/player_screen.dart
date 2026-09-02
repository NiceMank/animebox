import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/episode.dart';
import '../anime/data/models/episode_quality.dart';
import '../anime/data/models/season.dart';
import '../anime/data/models/video_quality.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../core/theme/app_colors.dart';
import '../media/models/media_access.dart';
import '../media/models/download_models.dart';
import '../media/services/download_manager.dart';
import '../media/services/media_service.dart';
import '../../shared/widgets/video_controls.dart';
import '../../app/router.dart';
import 'player_controller.dart';
import 'widgets/player_info_section.dart';
import 'widgets/player_next_episode.dart';
import 'widgets/player_other_qualities.dart';

/// Écran 6 — Lecteur vidéo RÉEL (prompt 8) :
/// - lecture locale du fichier téléchargé (hors connexion) ;
/// - lecture sur téléchargement TDLib (partiel contigu, bascule au fichier
///   final sans coupure de logique) ;
/// - repli honnête « Lecture directe indisponible » + Ouvrir dans Telegram ;
/// - sous-titres et pistes audio réels, volume, plein écran, progression
///   sauvegardée (position/durée/statut terminé).
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.repository,
    required this.animeId,
    required this.episodeId,
    this.mediaService,
    this.playerFactory = tryCreatePlayerController,
  });

  final AnimeRepository repository;
  final String animeId;
  final String episodeId;

  /// Couche média (null en démonstration : repli honnête affiché).
  final MediaService? mediaService;

  /// Fabrique du contrôleur réel (injectable pour les tests).
  final PlayerController? Function() playerFactory;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

/// Phase d'affichage de la zone vidéo (états réels, jamais simulés).
enum _VideoPhase { preparing, ready, waitingDownload, fallback, unavailable, incompatible }

class _PlayerScreenState extends State<PlayerScreen> {
  late final Anime _anime;
  late final Episode _episode;
  late EpisodeQuality _selectedVersion;

  PlayerController? _controller;
  _VideoPhase _phase = _VideoPhase.preparing;
  String? _phaseMessage;
  String? _failureMessage;
  StreamSubscription<void>? _completedSub;
  Timer? _saveTimer;
  Timer? _partialPollTimer;
  bool _controlsVisible = true;
  bool _isFullscreen = false;
  Timer? _autoHideTimer;

  int _autoNextSeconds = 3;
  Timer? _autoNextTimer;

  Anime get anime => _anime;
  Episode get episode => _episode;

  Season? get _season {
    final (Season, Episode)? located = _anime.locateEpisode(_episode.id);
    return located?.$1;
  }

  // ---------------------------------------------------------------------
  // Initialisation / préparation RÉELLE
  // ---------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _anime = widget.repository.byId(widget.animeId)!;
    _episode = _anime.episodeById(widget.episodeId)!;
    _selectedVersion = selectPreferredQuality(
      _episode,
      widget.repository.playbackSettings.preferredQuality,
    );
    // Orientation : portrait et paysage autorisés dans le lecteur.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final MediaService? media = widget.mediaService;
    if (media == null) {
      // Démonstration : aucune lecture réelle possible — repli honnête.
      _applyFallback(
        _selectedVersion.hasTelegramLink
            ? 'Lecture directe indisponible. Ouvrez la publication dans Telegram.'
            : 'Lecture directe indisponible dans ce mode.',
      );
      return;
    }
    try {
      final PlaybackPlan plan = await media.preparePlayback(
        anime: _anime,
        episode: _episode,
        version: _selectedVersion,
      );
      if (!mounted) return;
      switch (plan.kind) {
        case PlaybackKind.localFile:
          await _startEngine(plan.localPath!);
          return;
        case PlaybackKind.partialStream:
          await _startProgressivePlayback(media, plan);
          return;
        case PlaybackKind.telegramFallback:
          _phase = _VideoPhase.fallback;
          _phaseMessage = plan.message ?? 'Lecture directe indisponible.';
          break;
        case PlaybackKind.unavailable:
          _phase = _VideoPhase.unavailable;
          _failureMessage = plan.failure?.message ?? 'Ce média n\'est plus disponible sur Telegram.';
          break;
      }
      setState(() {});
    } on MediaAccessException catch (failure) {
      if (!mounted) return;
      _applyFallback(failure.message);
    } catch (_) {
      if (!mounted) return;
      _applyFallback('Le média est momentanément indisponible. Réessayez plus tard.');
    }
  }

  /// Lecture directe indisponible : message + repli Telegram si lien réel.
  void _applyFallback(String message) {
    _phase = _selectedVersion.hasTelegramLink ? _VideoPhase.fallback : _VideoPhase.unavailable;
    _phaseMessage = message;
    setState(() {});
  }

  /// Lecture sur téléchargement en cours : lance le téléchargement puis
  /// ouvre le lecteur dès qu'un préfixe contigu suffisant existe.
  Future<void> _startProgressivePlayback(MediaService media, PlaybackPlan plan) async {
    await media.startDownload(
      anime: _anime,
      season: _season ?? _fallbackSeason(),
      episode: _episode,
      version: _selectedVersion,
    );
    _phase = _VideoPhase.waitingDownload;
    _phaseMessage = 'Préparation de la lecture…';
    setState(() {});
    final int? fileId = plan.fileId;
    if (fileId == null) {
      _applyFallback('Lecture directe indisponible.');
      return;
    }
    // Sondage léger : état TDLib du fichier (préfixe contigu réel).
    _partialPollTimer?.cancel();
    _partialPollTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) async {
      final String? path = await media.partialPathFor(fileId);
      int prefixBytes = 0;
      if (path != null) {
        try {
          prefixBytes = File(path).lengthSync();
        } catch (_) {
          prefixBytes = 0;
        }
      }
      if (!mounted) {
        timer.cancel();
        return;
      }
      final DownloadTask? task = media.downloadManager.taskForVersion(_selectedVersion.id);
      if (task != null && task.status == DownloadStatus.completed && task.localPath != null) {
        timer.cancel();
        await _startEngine(task.localPath!);
        return;
      }
      if (task != null &&
          (task.status == DownloadStatus.failed && !task.resumable ||
              task.status == DownloadStatus.cancelled)) {
        timer.cancel();
        _applyFallback(task.error ?? 'Lecture directe indisponible.');
        return;
      }
      if (path != null && prefixBytes >= _minPlayableBytes) {
        timer.cancel();
        await _startEngine(path);
      }
    });
  }

  /// Préfixe minimal avant ouverture (2 Mo contigus — lecture démarrable
  /// sans interruption immédiate ; la progression réelle est affichée).
  static const int _minPlayableBytes = 2 * 1024 * 1024;

  Season _fallbackSeason() => Season(id: 's-unknown', number: _season?.number ?? 1, episodes: [_episode]);

  Future<void> _startEngine(String path) async {
    _phase = _VideoPhase.preparing;
    _phaseMessage = 'Chargement du média…';
    setState(() {});
    try {
      _controller ??= widget.playerFactory();
      final PlayerController? controller = _controller;
      if (controller == null) {
        _applyFallback('Lecture directe indisponible sur cet appareil.');
        return;
      }
      final Duration? saved = _resumePosition();
      await controller.open(path, initialPosition: saved);
      if (!mounted) return;
      _completedSub?.cancel();
      _completedSub = controller.onCompleted.listen((void _) => _onPlaybackCompleted());
      _phase = _VideoPhase.ready;
      _phaseMessage = null;
      _armAutoHide();
      _saveTimer?.cancel();
      _saveTimer = Timer.periodic(const Duration(seconds: 3), (Timer _) => _saveProgress());
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _phase = _VideoPhase.incompatible;
      _phaseMessage = 'Ce format vidéo n\'est pas compatible avec le lecteur.';
      setState(() {});
    }
  }

  /// Position de reprise : début si l'épisode a été terminé (règle 21),
  /// sinon la dernière position réellement enregistrée.
  Duration? _resumePosition() {
    final AnimeRepository repository = widget.repository;
    if (repository.playbackSettings.resumeFromLastPosition) {
      if (repository.episodeCompleted(_anime.id, _episode.id)) return Duration.zero;
      return repository.episodeProgress(_anime.id, _episode.id);
    }
    return Duration.zero;
  }

  // ---------------------------------------------------------------------
  // Progression de lecture (règles 21/22) — valeurs RÉELLES du lecteur
  // ---------------------------------------------------------------------

  void _saveProgress() {
    final PlayerController? controller = _controller;
    if (controller == null || !controller.isInitialized) return;
    final Duration position = controller.position;
    if (position <= Duration.zero) return;
    final Duration duration = controller.duration;
    widget.repository.recordProgress(
      _anime.id,
      _episode.id,
      position,
      duration: duration,
      completed: duration > Duration.zero && position >= duration - const Duration(seconds: 3),
    );
  }

  void _onPlaybackCompleted() {
    final PlayerController? controller = _controller;
    if (controller != null) {
      widget.repository.recordProgress(
        _anime.id,
        _episode.id,
        controller.duration,
        duration: controller.duration,
        completed: true,
      );
    }
    _maybeAutoNext();
  }

  // ---------------------------------------------------------------------
  // Lecture automatique (préparée à l'étape précédente — conservée)
  // ---------------------------------------------------------------------

  void _maybeAutoNext() {
    if (!widget.repository.playbackSettings.autoPlayNext) return;
    final Episode? next = _anime.nextEpisodeOf(_episode);
    if (next == null) return;
    _startAutoNext(next);
  }

  void _startAutoNext(Episode next) {
    setState(() => _autoNextSeconds = 3);
    _autoNextTimer?.cancel();
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_autoNextSeconds <= 1) {
        timer.cancel();
        _goToEpisode(next);
      } else {
        setState(() => _autoNextSeconds--);
      }
    });
  }

  void _goToEpisode(Episode next) {
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.episodeQuality,
      arguments: EpisodeRouteArgs(animeId: _anime.id, episodeId: next.id),
    );
  }

  // ---------------------------------------------------------------------
  // Navigation interne
  // ---------------------------------------------------------------------

  void _goToEpisodes() {
    final NavigatorState navigator = Navigator.of(context);
    bool found = false;
    navigator.popUntil((Route<dynamic> route) {
      if (route.settings.name == AppRoutes.animeEpisodes) {
        found = true;
        return true;
      }
      return route.isFirst;
    });
    if (!found) {
      navigator.pushReplacementNamed(
        AppRoutes.animeEpisodes,
        arguments: EpisodeListArgs(widget.animeId),
      );
    }
  }

  /// Retourne à l'écran de qualité (écran précédent dans la pile).
  void _goToQuality() => Navigator.of(context).maybePop();

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    setState(() => _isFullscreen = !_isFullscreen);
  }

  Future<bool> _onWillPop() async {
    if (_isFullscreen) {
      await _toggleFullscreen();
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------
  // Contrôles visibles / masqués
  // ---------------------------------------------------------------------

  void _onVideoTap() {
    setState(() => _controlsVisible = !_controlsVisible);
    _armAutoHide();
  }

  void _armAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller?.isPlaying == true) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  // ---------------------------------------------------------------------
  // Ouverture Telegram (repli — lien RÉEL uniquement)
  // ---------------------------------------------------------------------

  Future<void> _openTelegram() async {
    final MediaService? media = widget.mediaService;
    final String? error = await (media?.openTelegramLink(_selectedVersion.telegramMessageLink) ??
        Future<String?>.value('Aucun lien Telegram disponible pour cette version.'));
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  // ---------------------------------------------------------------------
  // Sélecteurs de pistes (sous-titres / audio) — pistes RÉELLES
  // ---------------------------------------------------------------------

  Future<void> _pickSubtitleTrack() async {
    final PlayerController? controller = _controller;
    if (controller == null) return;
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Sous-titres', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final PlayerTrack track in controller.subtitleTracks)
              ListTile(
                title: Text(track.label),
                subtitle: track.language == null ? null : Text(track.language!),
                trailing: controller.currentSubtitleTrackId == track.id
                    ? const Icon(Icons.check_rounded, color: AppColors.primaryBright)
                    : null,
                onTap: () => Navigator.of(context).pop(track.id),
              ),
            ListTile(
              leading: const Icon(Icons.subtitles_off_outlined),
              title: const Text('Désactivés'),
              trailing: controller.currentSubtitleTrackId == null
                  ? const Icon(Icons.check_rounded, color: AppColors.primaryBright)
                  : null,
              onTap: () => Navigator.of(context).pop(''),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await controller.setSubtitleTrack(selected.isEmpty ? null : selected);
  }

  Future<void> _pickAudioTrack() async {
    final PlayerController? controller = _controller;
    if (controller == null) return;
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Piste audio', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final PlayerTrack track in controller.audioTracks)
              ListTile(
                title: Text(track.label),
                subtitle: track.language == null ? null : Text(track.language!),
                onTap: () => Navigator.of(context).pop(track.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await controller.setAudioTrack(selected);
  }

  // ---------------------------------------------------------------------
  // Interface
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final List<EpisodeQuality> otherVersions = <EpisodeQuality>[
      for (final EpisodeQuality quality in _episode.availableQualities)
        if (quality.id != _selectedVersion.id) quality,
    ];

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && _isFullscreen) await _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isFullscreen
            ? _buildVideoArea()
            : Column(
                children: <Widget>[
                  _buildVideoArea(),
                  Expanded(child: _buildInfo(otherVersions)),
                ],
              ),
      ),
    );
  }

  Widget _buildVideoArea() {
    final PlayerController? listenable = _controller;
    final Widget videoArea = GestureDetector(
          onTap: _onVideoTap,
          child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (_phase == _VideoPhase.ready && _controller?.buildVideo(context) != null)
                      Positioned.fill(child: _controller!.buildVideo(context)!)
                    else
                      _buildStatusOverlay(),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: <double>[0.0, 0.18, 0.55, 0.85, 1.0],
                          colors: <Color>[
                            Color(0xB3000000),
                            Color(0x59000000),
                            Colors.transparent,
                            Color(0x59000000),
                            Color(0xB3000000),
                          ],
                        ),
                      ),
                    ),
                    if (_phase == _VideoPhase.ready) ..._buildControls(),
                    _buildTopBar(hasMedia: _phase == _VideoPhase.ready),
                  ],
                ),
              ),
            ),
          );
        return listenable == null
            ? videoArea
            : ListenableBuilder(listenable: listenable, builder: (BuildContext context, Widget? _) => videoArea);
  }

  /// Surcouche d'état : préparation, attente du préfixe, repli, erreur.
  Widget _buildStatusOverlay() {
    final DownloadTask? task = widget.mediaService?.downloadManager.taskForVersion(_selectedVersion.id);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_phase == _VideoPhase.preparing) ...<Widget>[
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryBright),
              ),
              const SizedBox(height: 12),
              Text(
                _phaseMessage ?? 'Préparation…',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: Colors.white70),
              ),
            ] else if (_phase == _VideoPhase.waitingDownload) ...<Widget>[
              const Icon(Icons.downloading_rounded, size: 34, color: AppColors.primaryBright),
              const SizedBox(height: 10),
              Text(
                'Préparation de la lecture…',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              if (task != null) ...<Widget>[
                const SizedBox(height: 10),
                SizedBox(
                  width: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: task.fraction,
                      minHeight: 5,
                      backgroundColor: Colors.white12,
                      color: AppColors.primaryBright,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  task.fraction == null
                      ? '${_megaOctets(task.downloadedBytes)} reçus'
                      : '${(task.fraction! * 100).round()} %',
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
              ],
            ] else ...<Widget>[
              const Icon(Icons.videocam_off_outlined, size: 34, color: AppColors.textSecondary),
              const SizedBox(height: 10),
              const Text(
                'Lecture directe indisponible.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              if (_phaseMessage != null || _failureMessage != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  _phaseMessage ?? _failureMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
              const SizedBox(height: 14),
              if (_selectedVersion.hasTelegramLink)
                FilledButton.icon(
                  key: const Key('player-open-telegram'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _openTelegram,
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text('Ouvrir dans Telegram'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _megaOctets(int bytes) {
    final double mb = bytes / (1024 * 1024);
    return mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} Go' : '${mb.round()} Mo';
  }

  List<Widget> _buildControls() {
    final PlayerController? controller = _controller;
    if (controller == null) return const <Widget>[];
    return <Widget>[
      Center(
        child: VideoControls(
          isPlaying: controller.isPlaying,
          position: controller.position,
          duration: controller.duration,
          volume: controller.volume,
          onVolumeChanged: (double value) => controller.setVolume(value),
          onTogglePlay: () {
            controller.togglePlay();
            _armAutoHide();
          },
          onSeek: (Duration target) {
            controller.seek(target);
            _armAutoHide();
          },
          onRewind10: () => controller.seekRelative(-const Duration(seconds: 10)),
          onForward10: () => controller.seekRelative(const Duration(seconds: 10)),
          onToggleFullscreen: _toggleFullscreen,
          isFullscreen: _isFullscreen,
        ),
      ),
    ];
  }

  Widget _buildTopBar({required bool hasMedia}) {
    final PlayerController? controller = _controller;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: <Widget>[
              _TopIcon(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Retour',
                onTap: () async {
                  final NavigatorState navigator = Navigator.of(context);
                  if (await _onWillPop()) navigator.maybePop();
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _videoTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              if (hasMedia && (controller?.subtitleTracks.isNotEmpty ?? false))
                _TopIcon(icon: Icons.subtitles_outlined, tooltip: 'Sous-titres', onTap: _pickSubtitleTrack),
              if (hasMedia && (controller?.audioTracks.length ?? 0) > 1)
                _TopIcon(icon: Icons.headset_outlined, tooltip: 'Piste audio', onTap: _pickAudioTrack),
              if (!hasMedia) ...<Widget>[
                const SizedBox(width: 4),
                _TopIcon(icon: Icons.more_vert_rounded, tooltip: 'Options', onTap: _goToQuality),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _videoTitle() {
    final int seasonNumber = _season?.number ?? 1;
    return '${_anime.title} S${seasonNumber.toString().padLeft(2, '0')}'
        'E${_episode.number.toString().padLeft(2, '0')}'
        ' · ${_selectedVersion.quality.label} · ${_selectedVersion.language}';
  }

  Widget _buildInfo(List<EpisodeQuality> otherVersions) {
    final Episode? next = _anime.nextEpisodeOf(_episode);
    final bool autoPlay = widget.repository.playbackSettings.autoPlayNext;
    final Season? season = _season;

    return Container(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
        children: <Widget>[
          PlayerInfoSection(
            repository: widget.repository,
            anime: _anime,
            episode: _episode,
            seasonNumber: season?.number,
            selectedQuality: _selectedVersion,
            onEpisodes: _goToEpisodes,
            onQuality: _goToQuality,
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              const Icon(Icons.autorenew_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Lecture automatique', style: Theme.of(context).textTheme.titleSmall),
                    Text('Enchaîner l\'épisode suivant', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
              Switch(
                value: autoPlay,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                activeThumbColor: AppColors.primaryBright,
                onChanged: (bool enabled) {
                  widget.repository.setAutoPlayNext(enabled);
                  setState(() {});
                },
              ),
            ],
          ),
          if (next != null) ...<Widget>[
            const SizedBox(height: 16),
            const Text(
              'Prochain épisode',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            PlayerNextEpisode(episode: next, onTap: () => _goToEpisode(next)),
          ],
          if (otherVersions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            PlayerOtherQualities(
              qualities: otherVersions,
              onDownload: (EpisodeQuality version) => _downloadVersion(version),
            ),
          ],
        ],
      ),
    );
  }

  /// Téléchargement réel d'une autre version (règles 8/19).
  Future<void> _downloadVersion(EpisodeQuality version) async {
    final MediaService? media = widget.mediaService;
    final Season? season = _season;
    if (media == null || season == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous à Telegram pour télécharger.')),
      );
      return;
    }
    final DownloadManagerResult result = await media.startDownload(
      anime: _anime,
      season: season,
      episode: _episode,
      version: version,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.ok ? 'Téléchargement lancé.' : 'Téléchargement impossible.'))),
    );
  }

  @override
  void dispose() {
    _saveProgress();
    _saveTimer?.cancel();
    _partialPollTimer?.cancel();
    _autoHideTimer?.cancel();
    _autoNextTimer?.cancel();
    _completedSub?.cancel();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 21, color: Colors.white),
      style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.35)),
    );
  }
}
