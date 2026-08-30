import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/anime/data/models/anime.dart';
import 'poster_image.dart';

/// Carte verticale d'un animé (poster + titre), utilisée dans les grilles.
class AnimeCard extends StatelessWidget {
  const AnimeCard({super.key, required this.anime, required this.onTap, this.width, this.progress});

  final Anime anime;
  final VoidCallback onTap;
  final double? width;

  /// Progression de visionnage (0..1), affichée sous le titre si non nulle.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Le poster occupe l'espace restant : la carte s'adapte ainsi à
            // toutes les hauteurs de grille sans jamais déborder.
            Expanded(
              child: PosterImage(asset: anime.posterAsset, fallbackLabel: anime.title),
            ),
            const SizedBox(height: 8),
            Text(
              anime.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(anime.episodeMeta, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
