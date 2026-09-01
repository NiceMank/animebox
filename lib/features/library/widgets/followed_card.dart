import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../anime/data/models/anime.dart';
import '../../anime/data/models/episode.dart';
import '../../anime/data/models/season.dart';
import '../../../shared/widgets/poster_image.dart';

/// Carte d'un animé suivi : progression des épisodes + dernier épisode
/// disponible + indicateur « NOUVEAU ».
class FollowedCard extends StatelessWidget {
  const FollowedCard({super.key, required this.anime, required this.onTap});

  final Anime anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Season? latestSeason = anime.seasons.isEmpty ? null : anime.seasons.last;
    final Episode? latestEpisode = anime.latestEpisode;
    final bool hasNew = latestEpisode?.isNew ?? false;
    final int available = latestSeason?.episodeCount ?? 0;
    // « X/24 disponibles » : épisodes publiés vs total annoncé par le
    // fournisseur (distinct des épisodes réellement sur Telegram).
    final int? announced = anime.totalEpisodesDeclared;

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
              PosterImage(asset: anime.posterAsset, url: anime.posterUrl, width: 72, height: 100, borderRadius: 12, fallbackLabel: anime.title),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            anime.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (hasNew) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: AppColors.accentGradient),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Text(
                              'NOUVEAU',
                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      latestSeason == null
                          ? 'Aucun épisode'
                          : 'Saison ${latestSeason.number} · Épisode ${latestEpisode?.number ?? 0} / $available',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (announced != null && announced != anime.totalEpisodes) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${anime.totalEpisodes} / $announced épisodes disponibles',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryBright),
                      ),
                    ],
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: available == 0 ? 0 : ((latestEpisode?.number ?? 0) / available).clamp(0, 1),
                        minHeight: 6,
                        backgroundColor: AppColors.divider,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      latestEpisode == null ? 'Aucun épisode disponible' : 'Dernier épisode disponible : Épisode ${latestEpisode.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
