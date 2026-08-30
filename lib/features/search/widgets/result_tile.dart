import 'package:flutter/material.dart';

import '../../anime/data/models/anime.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/poster_image.dart';

/// Ligne de résultat de recherche (poster, titre, saison, épisodes, genres).
class ResultTile extends StatelessWidget {
  const ResultTile({super.key, required this.anime, required this.onTap});

  final Anime anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool available = anime.latestEpisode != null;
    final List<String> visibleGenres = anime.genres.take(2).toList();
    final int extraGenres = anime.genres.length - visibleGenres.length;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              PosterImage(asset: anime.posterAsset, width: 60, height: 84, borderRadius: 12, fallbackLabel: anime.title),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(anime.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                        ),
                        const SizedBox(width: 8),
                        _AvailabilityDot(available: available),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(anime.episodeMeta, style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final String genre in visibleGenres) _GenreTag(label: genre),
                        if (extraGenres > 0) _GenreTag(label: '+$extraGenres'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreTag extends StatelessWidget {
  const _GenreTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
    );
  }
}

class _AvailabilityDot extends StatelessWidget {
  const _AvailabilityDot({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    final Color color = available ? AppColors.success : AppColors.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(available ? 'Disponible' : 'À venir', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}
