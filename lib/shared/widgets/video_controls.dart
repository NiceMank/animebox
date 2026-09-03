import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'player_progress_slider.dart';

/// Contrôles du lecteur vidéo : retour/avance 10 s, lecture/pause,
/// barre de progression, temps, volume, plein écran.
class VideoControls extends StatefulWidget {
  const VideoControls({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onRewind10,
    required this.onForward10,
    required this.onToggleFullscreen,
    this.volume,
    this.onVolumeChanged,
    this.isFullscreen = false,
  });

  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onRewind10;
  final VoidCallback onForward10;
  final VoidCallback onToggleFullscreen;
  final bool isFullscreen;

  /// Volume réel (0..100) et sa modification — null si non applicable.
  final double? volume;
  final ValueChanged<double>? onVolumeChanged;

  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls> {
  bool _volumeVisible = false;

  @override
  Widget build(BuildContext context) {
    final double? volume = widget.volume;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_volumeVisible && volume != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10, left: 24, right: 24),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Icon(
                  volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                Expanded(
                  child: Slider(
                    value: volume.clamp(0, 100),
                    max: 100,
                    activeColor: AppColors.primaryBright,
                    inactiveColor: AppColors.divider,
                    onChanged: (double value) => widget.onVolumeChanged?.call(value),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            _roundIcon(Icons.replay_10_rounded, widget.onRewind10, tooltip: 'Reculer de 10 s'),
            const SizedBox(width: 20),
            GestureDetector(
              key: const Key('player-toggle-play'),
              onTap: widget.onTogglePlay,
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: AppColors.primaryGradient),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 6))],
                ),
                child: Icon(
                  widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 20),
            _roundIcon(Icons.forward_10_rounded, widget.onForward10, tooltip: 'Avancer de 10 s'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                formatDuration(widget.position),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: PlayerProgressSlider(position: widget.position, duration: widget.duration, onSeek: widget.onSeek),
            ),
            SizedBox(
              width: 44,
              child: Text(
                formatDuration(widget.duration),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 6),
            if (volume != null)
              _roundIcon(
                _volumeVisible ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                () => setState(() => _volumeVisible = !_volumeVisible),
                size: 20,
                tooltip: 'Volume',
              ),
            if (volume != null) const SizedBox(width: 2),
            _roundIcon(
              widget.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              widget.onToggleFullscreen,
              size: 20,
              tooltip: widget.isFullscreen ? 'Quitter le plein écran' : 'Plein écran',
            ),
          ],
        ),
      ],
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap, {double size = 22, String? tooltip}) {
    return Semantics(
      button: true,
      label: tooltip,
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, size: size, color: AppColors.textPrimary),
      ),
    );
  }
}
