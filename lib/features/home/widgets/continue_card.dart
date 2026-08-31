import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../anime/data/models/anime.dart';
import '../../anime/data/models/episode.dart';
import '../../anime/data/models/library_entry.dart';
import '../../../shared/widgets/episode_thumbnail.dart';
import '../../../shared/widgets/player_progress_slider.dart';

/// Carte « Continuer » : reprise de visionnage d'un épisode.
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.entry, required this.onTap});

  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Anime anime = entry.anime;
    final Episode? episode = entry.resumeEpisode;
    final Duration? position = entry.resumePosition;
    final double? fraction = entry.resumeFraction();

    return Material(
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
            children: [
              EpisodeThumbnail(
                asset: episode?.thumbnail ?? anime.posterAsset,
                width: 112,
                height: 64,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(anime.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 3),
                    Text(
                      episode == null
                          ? 'Non commencé'
                          : '${episode.label} · Reprendre à ${formatDuration(position ?? Duration.zero)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primaryBright),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction ?? 0,
                        minHeight: 5,
                        backgroundColor: AppColors.divider,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_circle_fill_rounded, color: AppColors.primaryBright, size: 34),
            ],
          ),
        ),
      ),
    );
  }
}
