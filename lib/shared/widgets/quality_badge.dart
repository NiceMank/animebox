import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/anime/data/models/video_quality.dart';

/// Pastille de qualité vidéo (1080p, 720p, 480p).
class QualityBadge extends StatelessWidget {
  const QualityBadge(this.quality, {super.key, this.compact = false});

  final VideoQuality quality;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (Color text, Color background, Color border) = switch (quality) {
      VideoQuality.fhd => (
          AppColors.primaryBright,
          AppColors.primary.withValues(alpha: 0.16),
          AppColors.primary.withValues(alpha: 0.55),
        ),
      VideoQuality.hd => (
          AppColors.textSecondary,
          AppColors.textSecondary.withValues(alpha: 0.12),
          AppColors.divider,
        ),
      VideoQuality.sd => (
          AppColors.textMuted,
          AppColors.textMuted.withValues(alpha: 0.12),
          AppColors.divider,
        ),
      VideoQuality.low => (
          AppColors.textMuted,
          AppColors.textMuted.withValues(alpha: 0.12),
          AppColors.divider,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: compact ? 2.5 : 4),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Text(
        quality.label,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: text,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
