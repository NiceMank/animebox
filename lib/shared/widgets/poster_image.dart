import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Affiche un asset image avec coins arrondis et un dégradé de secours
/// si l'image est introuvable.
class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.asset,
    this.fit = BoxFit.cover,
    this.borderRadius = 16,
    this.width,
    this.height,
    this.fallbackLabel,
  });

  final String asset;
  final BoxFit fit;
  final double borderRadius;
  final double? width;
  final double? height;

  /// Titre affiché sur le fond de secours (première lettre).
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.asset(
          asset,
          fit: fit,
          width: width,
          height: height,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _FallbackPoster(label: fallbackLabel),
        ),
      ),
    );
  }
}

class _FallbackPoster extends StatelessWidget {
  const _FallbackPoster({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceAlt, AppColors.surface],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        (label?.isNotEmpty ?? false) ? label![0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textMuted),
      ),
    );
  }
}
