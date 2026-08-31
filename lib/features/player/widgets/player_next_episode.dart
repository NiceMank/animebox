import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../anime/data/models/episode.dart';
import '../../../shared/widgets/episode_thumbnail.dart';

/// Carte « Prochain épisode » sous le lecteur.
class PlayerNextEpisode extends StatelessWidget {
  const PlayerNextEpisode({super.key, required this.episode, required this.onTap});

  final Episode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              EpisodeThumbnail(asset: episode.thumbnail, width: 108, height: 62, borderRadius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Épisode ${episode.number}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryBright),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      episode.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: AppColors.primaryBright, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
