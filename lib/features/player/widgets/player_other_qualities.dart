import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../anime/data/models/episode_quality.dart';
import '../../anime/data/models/video_quality.dart';

/// Section « Autres qualités disponibles » sous le lecteur.
class PlayerOtherQualities extends StatelessWidget {
  const PlayerOtherQualities({
    super.key,
    required this.qualities,
    required this.onDownload,
  });

  /// Qualités proposées en plus de la qualité en cours de lecture.
  final List<EpisodeQuality> qualities;
  final ValueChanged<EpisodeQuality> onDownload;

  @override
  Widget build(BuildContext context) {
    if (qualities.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Autres qualités disponibles',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        for (final EpisodeQuality quality in qualities) ...[
          _QualityRow(
            quality: quality,
            onDownload: () => onDownload(quality),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.quality, required this.onDownload});

  final EpisodeQuality quality;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final VideoQuality videoQuality = quality.quality;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Text(
            videoQuality.label,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.primaryBright),
          ),
          const SizedBox(width: 8),
          Text(
            '— ${quality.sizeLabel}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          IconButton(
            onPressed: onDownload,
            tooltip: 'Télécharger en ${videoQuality.label}',
            icon: Icon(Icons.download_rounded, size: 19, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
