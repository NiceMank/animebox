import 'package:flutter/material.dart';

import '../../anime/data/models/anime.dart';
import '../../anime/data/models/episode.dart';
import '../../anime/data/models/video_quality.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/poster_image.dart';
import '../../../shared/widgets/quality_badge.dart';
import '../../../shared/widgets/status_pill.dart';

/// Grande carte mise en avant (nouvel épisode) du carousel d'accueil.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.anime, required this.onOpen});

  final Anime anime;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final Episode? episode = anime.latestEpisode;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PosterImage(asset: anime.backdropAsset, borderRadius: 0, fallbackLabel: anime.title),
          // Voile dégradé pour la lisibilité du texte.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.45, 1.0],
                colors: [Colors.transparent, Color(0x330A0817), Color(0xF20A0817)],
              ),
            ),
          ),
          const Positioned(top: 16, left: 16, child: StatusPill('Nouvel épisode', filled: true)),
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anime.title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        shadows: const [Shadow(color: Colors.black54, blurRadius: 12)],
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  episode == null
                      ? 'Bientôt disponible'
                      : '${anime.latestEpisodeTag} · ${episode.qualities.first.label} · ${anime.languages.first}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(label: 'Voir la fiche', icon: Icons.arrow_forward_rounded, onTap: onOpen),
                    ),
                    if (episode != null) ...[
                      const SizedBox(width: 10),
                      QualityBadge(episode.qualities.first),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
