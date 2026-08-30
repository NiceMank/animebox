import 'package:flutter/material.dart';

import '../../anime/data/models/anime.dart';
import '../../anime/data/models/library_entry.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/poster_image.dart';

/// Carte « Continuer » : progression de visionnage d'un épisode.
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.entry, required this.onTap});

  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Anime anime = entry.anime;
    final int percent = (entry.progress * 100).round();

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              PosterImage(asset: anime.posterAsset, width: 56, height: 76, borderRadius: 12, fallbackLabel: anime.title),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(anime.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      entry.lastWatched == null ? 'Non commencé' : '${entry.lastWatched!.label} · $percent %',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: entry.progress,
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
