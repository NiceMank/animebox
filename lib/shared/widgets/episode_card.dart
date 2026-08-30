import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/anime/data/models/episode.dart';
import 'quality_badge.dart';

/// Ligne d'épisode (utilisée dans l'onglet Épisodes de la fiche animé).
///
/// La lecture et le téléchargement seront branchés dans une étape ultérieure.
class EpisodeCard extends StatelessWidget {
  const EpisodeCard({super.key, required this.episode, this.onTap});

  final Episode episode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  episode.number.toString().padLeft(2, '0'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryBright),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title ?? 'Épisode ${episode.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final quality in episode.qualities) QualityBadge(quality, compact: true)],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
