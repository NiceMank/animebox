import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/anime/data/models/episode.dart';
import '../../features/anime/data/models/video_quality.dart';
import 'episode_thumbnail.dart';
import 'quality_badge.dart';

/// Carte d'épisode réutilisable (liste d'épisodes, fiche animé) :
/// miniature, numéro, titre, date, badge « NOUVEAU », qualités disponibles
/// (un seul épisode = plusieurs qualités), progression éventuelle.
class EpisodeCard extends StatelessWidget {
  const EpisodeCard({
    super.key,
    required this.episode,
    this.onTap,
    this.progress,
    this.subtitle,
  });

  final Episode episode;
  final VoidCallback? onTap;

  /// Progression de lecture enregistrée (barre + « Reprendre à … »).
  final Duration? progress;

  /// Texte secondaire optionnel remplaçant la date (ex. « Spécial »).
  final String? subtitle;

  static const List<String> _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];

  String _formatDate(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';

  @override
  Widget build(BuildContext context) {
    final List<VideoQuality> badgeQualities = [
      for (final quality in episode.qualities) quality.quality,
    ];
    final bool hasProgress = progress != null && progress! > Duration.zero;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EpisodeThumbnail(asset: episode.thumbnail, width: 116, height: 68),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            episode.title ?? 'Épisode ${episode.number}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (episode.isNew) ...[
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
                      subtitle ?? _formatDate(episode.date),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final VideoQuality quality in badgeQualities) QualityBadge(quality, compact: true),
                      ],
                    ),
                    if (hasProgress) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _fraction(context),
                          minHeight: 4,
                          backgroundColor: AppColors.divider,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  hasProgress ? Icons.play_circle_fill_rounded : Icons.chevron_right_rounded,
                  color: hasProgress ? AppColors.primaryBright : AppColors.textMuted,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double? _fraction(BuildContext context) {
    if (progress == null) return null;
    final double total = Duration(minutes: 24).inMilliseconds.toDouble();
    return (progress!.inMilliseconds / total).clamp(0.01, 1.0);
  }
}
