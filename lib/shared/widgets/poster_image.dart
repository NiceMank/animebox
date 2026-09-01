import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Affiche une image (asset local OU URL du cache d'images backend) avec
/// coins arrondis, chargement progressif et un dégradé de secours si
/// l'image est introuvable.
class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.asset,
    this.url,
    this.fit = BoxFit.cover,
    this.borderRadius = 16,
    this.width,
    this.height,
    this.fallbackLabel,
  });

  final String asset;

  /// URL distante (poster/backdrop fournis par le catalogue) — prioritaire
  /// sur l'asset local quand elle est renseignée.
  final String? url;

  final BoxFit fit;
  final double borderRadius;
  final double? width;
  final double? height;

  /// Titre affiché sur le fond de secours (première lettre).
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final Widget image = url == null || url!.isEmpty
        ? Image.asset(
            asset,
            fit: fit,
            width: width,
            height: height,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _FallbackPoster(label: fallbackLabel),
          )
        : Image.network(
            url!,
            fit: fit,
            width: width,
            height: height,
            gaplessPlayback: true,
            // Chargement progressif : léger fondu quand l'image arrive.
            loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? progress) {
              if (progress == null) return child;
              return Stack(
                fit: StackFit.expand,
                children: [
                  _FallbackPoster(label: fallbackLabel),
                  Opacity(
                    opacity: progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1),
                    child: child,
                  ),
                ],
              );
            },
            errorBuilder: (_, _, _) => Image.asset(
              asset,
              fit: fit,
              width: width,
              height: height,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _FallbackPoster(label: fallbackLabel),
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: width, height: height, child: image),
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
