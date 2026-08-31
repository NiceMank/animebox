import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'player_progress_slider.dart';

/// Contrôles du lecteur vidéo : retour/avance 10 s, lecture/pause,
/// barre de progression, temps, plein écran.
class VideoControls extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _roundIcon(Icons.replay_10_rounded, onRewind10, tooltip: 'Reculer de 10 s'),
            const SizedBox(width: 20),
            GestureDetector(
              key: const Key('player-toggle-play'),
              onTap: onTogglePlay,
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.primaryGradient),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 6))],
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 20),
            _roundIcon(Icons.forward_10_rounded, onForward10, tooltip: 'Avancer de 10 s'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                formatDuration(position),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: PlayerProgressSlider(position: position, duration: duration, onSeek: onSeek),
            ),
            SizedBox(
              width: 44,
              child: Text(
                formatDuration(duration),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 6),
            _roundIcon(
              isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              onToggleFullscreen,
              size: 20,
              tooltip: isFullscreen ? 'Quitter le plein écran' : 'Plein écran',
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
