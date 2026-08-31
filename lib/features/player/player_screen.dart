import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/episode.dart';
import '../anime/data/models/episode_quality.dart';
import '../anime/data/models/season.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/video_controls.dart';
import 'playback_controller.dart';
import 'widgets/player_info_section.dart';
import 'widgets/player_next_episode.dart';
import 'widgets/player_other_qualities.dart';

/// Écran 6 — Lecteur vidéo (placeholder) : contrôles complets, informations
/// sous la vidéo, actions, prochain épisode, autres qualités et préparation
/// de la lecture automatique.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.repository,
    required this.animeId,
    required this.episodeId,
  });

  final AnimeRepository repository;
  final String animeId;
  final String episodeId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Anime _anime;
  late final Episode _episode;
  late final PlaybackController _controller;

  bool _controlsVisible = true;
  bool _isFullscreen = false;

  bool _autoNextPending = false;
  int _autoNextSeconds = 3;
  Timer? _autoNextTimer;

  int _ticksSinceSave = 0;

  Anime get anime => _anime;
  Episode get episode => _episode;

  Season? get _season {
    final (Season, Episode)? located = _anime.locateEpisode(_episode.id);
    return located?.$1;
  }

  @override
  void initState() {
    super.initState();
    _anime = widget.repository.byId(widget.animeId)!;
    _episode = _anime.episodeById(widget.episodeId)!;

    final Duration duration = Duration(minutes: _anime.episodeDurationMin.toInt());
    final Duration? saved = widget.repository.episodeProgress(_anime.id, _episode.id);
    _controller = PlaybackController(
      duration: duration,
      initialPosition: saved ?? Duration.zero,
      onProgress: _onProgress,
      onCompleted: _onCompleted,
    );
  }

  @override
  void dispose() {
    _autoNextTimer?.cancel();
    _saveProgressNow();
    _controller.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Progression de lecture
  // -------------------------------------------------------------------

  void _onProgress(Duration position) {
    // Sauvegarde périodique (toutes les ~2,5 s de lecture simulée).
    if (++_ticksSinceSave >= 5) {
      _ticksSinceSave = 0;
      _saveProgressNow();
    }
  }

  void _saveProgressNow() {
    if (_controller.position <= Duration.zero) return;
    final Duration position = _controller.position;
    // Différé : la sauvegarde peut être déclenchée depuis dispose(),
    // au moment où l'arbre est en cours de démontage.
    Future<void>.microtask(() {
      widget.repository.recordProgress(_anime.id, _episode.id, position);
    });
  }

  // -------------------------------------------------------------------
  // Lecture automatique (structure préparée)
  // -------------------------------------------------------------------

  void _onCompleted() {
    _saveProgressNow();
    if (!widget.repository.playbackSettings.autoPlayNext) return;
    final Episode? next = _anime.nextEpisodeOf(_episode);
    if (next == null) return;
    _startAutoNext(next);
  }

  void _startAutoNext(Episode next) {
    setState(() {
      _autoNextPending = true;
      _autoNextSeconds = 3;
    });
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

  void _cancelAutoNext() {
    _autoNextTimer?.cancel();
    setState(() => _autoNextPending = false);
  }

  void _goToEpisode(Episode next) {
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.episodeQuality,
      arguments: EpisodeRouteArgs(animeId: _anime.id, episodeId: next.id),
    );
  }

  // -------------------------------------------------------------------
  // Navigation interne
  // -------------------------------------------------------------------

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
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    setState(() => _isFullscreen = !_isFullscreen);
  }

  // -------------------------------------------------------------------
  // Contrôles visibles / masqués
  // -------------------------------------------------------------------

  /// Un appui sur la vidéo bascule l'affichage des contrôles.
  void _onVideoTap() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  // -------------------------------------------------------------------
  // Interface
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final EpisodeQuality? selected =
        _episode.bestQuality ?? _episode.qualities.firstOrNull;
    if (selected == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Aucune qualité disponible')));
    }
    final List<EpisodeQuality> otherQualities = [
      for (final EpisodeQuality quality in _episode.availableQualities)
        if (quality.id != selected.id) quality,
    ];

    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        final Widget videoArea = _VideoArea(
          anime: _anime,
          episode: _episode,
          controller: _controller,
          controlsVisible: _controlsVisible || _autoNextPending,
          isFullscreen: _isFullscreen,
          onTap: _onVideoTap,
          onBack: () => Navigator.of(context).maybePop(),
          onToggleFullscreen: _toggleFullscreen,
          onQuality: _goToQuality,
          onUserInteracted: _cancelAutoNext,
        );

        return Scaffold(
          backgroundColor: Colors.black,
          body: _isFullscreen
              ? videoArea
              : Column(
                  children: [
                    videoArea,
                    Expanded(child: _buildInfo(selected, otherQualities)),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildInfo(EpisodeQuality selected, List<EpisodeQuality> otherQualities) {
    final Episode? next = _anime.nextEpisodeOf(_episode);
    final bool autoPlay = widget.repository.playbackSettings.autoPlayNext;
    final Season? season = _season;

    return Container(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
        children: [
          PlayerInfoSection(
            repository: widget.repository,
            anime: _anime,
            episode: _episode,
            seasonNumber: season?.number,
            selectedQuality: selected,
            onEpisodes: _goToEpisodes,
            onQuality: _goToQuality,
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.autorenew_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
          if (next != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Prochain épisode',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            PlayerNextEpisode(episode: next, onTap: () => _goToEpisode(next)),
          ],
          if (otherQualities.isNotEmpty) ...[
            const SizedBox(height: 18),
            PlayerOtherQualities(
              qualities: otherQualities,
              onDownload: (_) => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Téléchargement en préparation…')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Zone vidéo (frame simulé) + barre supérieure + contrôles + overlay
/// de lecture automatique.
class _VideoArea extends StatelessWidget {
  const _VideoArea({
    required this.anime,
    required this.episode,
    required this.controller,
    required this.controlsVisible,
    required this.isFullscreen,
    required this.onTap,
    required this.onBack,
    required this.onToggleFullscreen,
    required this.onQuality,
    required this.onUserInteracted,
  });

  final Anime anime;
  final Episode episode;
  final PlaybackController controller;
  final bool controlsVisible;
  final bool isFullscreen;
  final VoidCallback onTap;
  final VoidCallback onBack;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onQuality;
  final VoidCallback onUserInteracted;

  @override
  Widget build(BuildContext context) {
    final String title = '${anime.title} S${_seasonNumber(anime, episode).toString().padLeft(2, '0')}'
        'E${episode.number.toString().padLeft(2, '0')}';

    return AspectRatio(
      aspectRatio: isFullscreen ? MediaQuery.of(context).size.aspectRatio : 16 / 9,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          onTap();
          onUserInteracted();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              anime.backdropAsset,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Container(color: AppColors.surface),
            ),
            // Voiles haut/bas pour la lisibilité des contrôles.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.18, 0.55, 0.85, 1.0],
                  colors: [
                    Color(0xB3000000),
                    Color(0x59000000),
                    Colors.transparent,
                    Color(0x59000000),
                    Color(0xB3000000),
                  ],
                ),
              ),
            ),
            if (controlsVisible) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        _TopIcon(icon: Icons.arrow_back_rounded, tooltip: 'Retour', onTap: onBack),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        _TopIcon(icon: Icons.subtitles_outlined, tooltip: 'Sous-titres', onTap: onUserInteracted),
                        const SizedBox(width: 4),
                        _TopIcon(icon: Icons.cast_rounded, tooltip: 'Diffuser', onTap: onUserInteracted),
                        const SizedBox(width: 4),
                        _TopIcon(icon: Icons.more_vert_rounded, tooltip: 'Options', onTap: onQuality),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: VideoControls(
                  isPlaying: controller.isPlaying,
                  position: controller.position,
                  duration: controller.duration,
                  onTogglePlay: () {
                    controller.togglePlay();
                    onUserInteracted();
                  },
                  onSeek: (Duration target) {
                    controller.seekTo(target);
                    onUserInteracted();
                  },
                  onRewind10: () {
                    controller.seekRelative(-const Duration(seconds: 10));
                    onUserInteracted();
                  },
                  onForward10: () {
                    controller.seekRelative(const Duration(seconds: 10));
                    onUserInteracted();
                  },
                  onToggleFullscreen: onToggleFullscreen,
                  isFullscreen: isFullscreen,
                ),
              ),
            ],
            if (!controlsVisible && !controller.isPlaying)
              Center(
                child: GestureDetector(
                  onTap: () {
                    controller.togglePlay();
                    onUserInteracted();
                  },
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: AppColors.primaryGradient),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, size: 34, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _seasonNumber(Anime anime, Episode episode) {
    final (Season, Episode)? located = anime.locateEpisode(episode.id);
    return located?.$1.number ?? 1;
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
