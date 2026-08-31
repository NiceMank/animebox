import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formats.dart';
import '../../features/telegram/data/models/sync_progress.dart';

/// Carte de progression d'une synchronisation en cours.
class SyncProgressCard extends StatelessWidget {
  const SyncProgressCard({super.key, required this.progress, this.finished = false, this.resultEpisodes});

  final SyncProgress progress;

  /// `true` quand l'analyse est terminée (phase « Analyse terminée »).
  final bool finished;

  /// Nouveaux épisodes détectés (affichés à la fin).
  final int? resultEpisodes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: finished ? AppColors.success.withValues(alpha: 0.45) : AppColors.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (finished)
                const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success)
              else
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primaryBright),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  finished ? 'Analyse terminée' : progress.phase,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: finished ? AppColors.success : AppColors.primaryBright,
                  ),
                ),
              ),
              Text('${progress.percent} %', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress.fraction.clamp(0, 1),
              minHeight: 8,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(finished ? AppColors.success : AppColors.primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${formatCount(progress.analyzedPosts)} / ${formatCount(progress.totalPosts)} publications',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (finished && resultEpisodes != null) ...[
            const SizedBox(height: 10),
            Text(
              '✓ $resultEpisodes nouveaux épisodes détectés.',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success),
            ),
          ],
        ],
      ),
    );
  }
}
