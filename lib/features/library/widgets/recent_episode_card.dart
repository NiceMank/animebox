import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../anime/data/models/anime.dart';
import '../../anime/data/models/episode.dart';
import '../../../shared/widgets/episode_thumbnail.dart';

/// Carte « Récemment ajouté » : dernier épisode détecté d'un animé.
class RecentEpisodeCard extends StatelessWidget {
  const RecentEpisodeCard({super.key, required this.anime, required this.onTap});

  final Anime anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Episode? episode = anime.latestEpisode;
    final String episodeLabel = episode == null ? '—' : 'S${anime.seasons.last.number}E${episode.number.toString().padLeft(2, '0')}';

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
              EpisodeThumbnail(asset: episode?.thumbnail ?? anime.posterAsset, width: 104, height: 60, borderRadius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.fiber_new_rounded, size: 15, color: AppColors.primaryBright),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            anime.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(episodeLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryBright)),
                    const SizedBox(height: 2),
                    Text(
                      episode?.title ?? 'Nouvel épisode disponible',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
