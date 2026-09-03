import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Vignette d'épisode (16:9, coins arrondis) avec un repli si l'image
/// est introuvable.
class EpisodeThumbnail extends StatelessWidget {
  const EpisodeThumbnail({
    super.key,
    required this.asset,
    this.width,
    this.height,
    this.borderRadius = 12,
    this.durationLabel,
  });

  final String asset;
  final double? width;
  final double? height;
  final double borderRadius;

  /// Durée affichée en bas à droite (optionnelle).
  final String? durationLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.surfaceAlt, AppColors.surface],
                  ),
                ),
                child: Icon(Icons.movie_rounded, color: AppColors.textMuted, size: 22),
              ),
            ),
            if (durationLabel != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    durationLabel!,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
