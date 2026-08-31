import 'package:flutter/material.dart';

import '../../anime/data/models/anime.dart';
import '../../anime/data/models/episode.dart';
import '../../anime/data/models/episode_quality.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/poster_image.dart';
import '../../../shared/widgets/quality_badge.dart';
import '../../../shared/widgets/status_pill.dart';

/// Carte horizontale d'un nouvel épisode (section « Nouveaux épisodes »).
class ReleaseCard extends StatelessWidget {
  const ReleaseCard({super.key, required this.anime, required this.onTap});

  final Anime anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Episode? episode = anime.latestEpisode;
    final List<QualityBadge> qualities = [
      for (final EpisodeQuality quality in episode?.qualities ?? const <EpisodeQuality>[])
        QualityBadge(quality.quality, compact: true),
    ];

    return SizedBox(
      width: 292,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PosterImage(asset: anime.posterAsset, width: 92, height: 132, borderRadius: 14, fallbackLabel: anime.title),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        anime.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        anime.latestEpisodeShortTag,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryBright),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          ...qualities.take(2),
                          if (anime.languages.isNotEmpty) StatusPill.language(anime.languages.first),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
