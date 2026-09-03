import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../anime/data/models/anime.dart';
import '../../anime/data/models/episode.dart';
import '../../anime/data/models/episode_quality.dart';
import '../../anime/data/models/video_quality.dart';
import '../../anime/data/repositories/anime_repository.dart';
import '../../../shared/widgets/action_button.dart';
import '../../../shared/widgets/telegram_placeholder_sheet.dart';

/// En-tête d'information sous la vidéo + rangée d'actions du lecteur.
class PlayerInfoSection extends StatelessWidget {
  const PlayerInfoSection({
    super.key,
    required this.repository,
    required this.anime,
    required this.episode,
    required this.seasonNumber,
    required this.selectedQuality,
    required this.onEpisodes,
    required this.onQuality,
  });

  final AnimeRepository repository;
  final Anime anime;
  final Episode episode;
  final int? seasonNumber;
  final EpisodeQuality selectedQuality;
  final VoidCallback onEpisodes;
  final VoidCallback onQuality;

  @override
  Widget build(BuildContext context) {
    final bool isFavorite = repository.libraryEntryFor(anime.id)?.isFavorite ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.label,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryBright),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    episode.title ?? anime.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      if (seasonNumber != null) 'Saison $seasonNumber',
                      selectedQuality.quality.label,
                      selectedQuality.language,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _DownloadButton(
              sizeLabel: selectedQuality.sizeLabel,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Téléchargement en préparation…')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label: 'Favori',
                active: isFavorite,
                onTap: () => repository.toggleFavorite(anime.id),
              ),
            ),
            Expanded(
              child: ActionButton(
                icon: Icons.download_rounded,
                label: 'Télécharger',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Téléchargement en préparation…')),
                ),
              ),
            ),
            Expanded(
              child: ActionButton(
                icon: Icons.send_rounded,
                label: 'Telegram',
                onTap: () => TelegramPlaceholderSheet.show(context),
              ),
            ),
            Expanded(
              child: ActionButton(
                key: const Key('player-action-episodes'),
                icon: Icons.format_list_bulleted_rounded,
                label: 'Épisodes',
                highlight: true,
                onTap: onEpisodes,
              ),
            ),
            Expanded(
              child: ActionButton(
                key: const Key('player-action-quality'),
                icon: Icons.hd_rounded,
                label: 'Qualité',
                highlight: true,
                onTap: onQuality,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.sizeLabel, required this.onTap});

  final String sizeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: AppColors.primaryGradient),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 7),
            Text(sizeLabel, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
