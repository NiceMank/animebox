import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Barre de progression vidéo personnalisée (glissable).
class PlayerProgressSlider extends StatelessWidget {
  const PlayerProgressSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.previewPosition,
  });

  final Duration position;
  final Duration duration;

  /// Position temporaire pendant le glissement (null hors glissement).
  final Duration? previewPosition;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final Duration shown = previewPosition ?? position;
    final double maxMilliseconds = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3.2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.textMuted.withValues(alpha: 0.28),
        thumbColor: AppColors.primaryBright,
        overlayColor: AppColors.primary.withValues(alpha: 0.18),
      ),
      child: Slider(
        min: 0,
        max: maxMilliseconds,
        value: shown.inMilliseconds.toDouble().clamp(0, maxMilliseconds),
        onChanged: duration.inMilliseconds > 0
            ? (double value) => onSeek(Duration(milliseconds: value.round()))
            : null,
      ),
    );
  }
}

/// Formate une durée en « h:mm:ss » ou « m:ss ».
String formatDuration(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  final int seconds = duration.inSeconds.remainder(60);
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '$minutes:${two(seconds)}';
}
