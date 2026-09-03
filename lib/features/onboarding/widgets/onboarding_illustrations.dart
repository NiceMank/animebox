import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/neon_box.dart';
import '../../../shared/widgets/quality_badge.dart';
import '../../../shared/widgets/telegram_logo.dart';
import '../../anime/data/models/video_quality.dart';

/// Cube AnimeBox hexagonal (logo vectoriel vectorisé de la marque) —
/// aucun emoji ni icône générique (règle du prompt 13).
class AnimeBoxCube extends StatelessWidget {
  const AnimeBoxCube({super.key, this.size = 92});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Logo AnimeBox',
      child: CustomPaint(size: Size.square(size), painter: _CubePainter()),
    );
  }
}

class _CubePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final Rect hex = Offset.zero & size;

    // Hexagone (contour dégradé bleu — identité visuelle du projet).
    final Path hexPath = Path();
    for (int i = 0; i < 6; i++) {
      final double angle = (60 * i - 30) * math.pi / 180;
      final double x = w / 2 + (w / 2 - w * 0.06) * math.cos(angle);
      final double y = w / 2 + (w / 2 - w * 0.06) * math.sin(angle);
      if (i == 0) {
        hexPath.moveTo(x, y);
      } else {
        hexPath.lineTo(x, y);
      }
    }
    hexPath.close();

    final Paint fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[AppColors.primaryDark, AppColors.primary],
      ).createShader(hex)
      ..style = PaintingStyle.fill
      ..strokeWidth = w * 0.05;
    canvas.drawShadow(hexPath, AppColors.primary, w * 0.22, true);
    canvas.drawPath(hexPath, fill..style = PaintingStyle.stroke);

    // Cube central (trois faces visibles — style maquette).
    final Paint cubeFace = Paint()..color = AppColors.primaryBright;
    final Paint cubeDark = Paint()..color = AppColors.primaryDark;
    final double cx = w / 2, cy = w / 2, r = w * 0.185, v = r * 0.55;
    final Path top = Path()
      ..moveTo(cx, cy - v - r * 0.45)
      ..lineTo(cx + r, cy - v)
      ..lineTo(cx, cy - v + r * 0.45)
      ..lineTo(cx - r, cy - v)
      ..close();
    final Path left = Path()
      ..moveTo(cx - r, cy - v)
      ..lineTo(cx, cy - v + r * 0.45)
      ..lineTo(cx, cy + v + r * 0.45)
      ..lineTo(cx - r, cy + v)
      ..close();
    final Path right = Path()
      ..moveTo(cx + r, cy - v)
      ..lineTo(cx, cy - v + r * 0.45)
      ..lineTo(cx, cy + v + r * 0.45)
      ..lineTo(cx + r, cy + v)
      ..close();
    canvas.drawPath(top, cubeFace);
    canvas.drawPath(left, cubeDark);
    canvas.drawPath(right, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Illustration de l'écran 1 : affiches réelles du catalogue existant
/// (compositions déjà présentes dans l'application) + logo au centre.
class OnboardingHeroArt extends StatelessWidget {
  const OnboardingHeroArt({super.key, this.height = 230});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(alignment: Alignment.center, children: <Widget>[
        Row(children: <Widget>[
          const _RealPoster('assets/img/poster_solo_leveling.png'),
          const SizedBox(width: 10),
          const _RealPoster('assets/img/poster_one_piece.png'),
        ]),
        // Fondu doux pour laisser respirer le logo (style maquette).
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: <Color>[
                  Colors.transparent,
                  AppColors.background.withValues(alpha: 0.55),
                ],
                radius: 1.1,
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const AnimeBoxCube(size: 74),
      ]),
    );
  }
}

class _RealPoster extends StatelessWidget {
  const _RealPoster(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          height: double.infinity,
          errorBuilder: (_, _, _) => Container(color: AppColors.surface),
        ),
      ),
    );
  }
}

/// Illustration de l'écran 2 : cube AnimeBox lumineux + badges qualité
/// réels de l'app (composants existants — pas de GeneralGlass).
class OnboardingCubeArt extends StatelessWidget {
  const OnboardingCubeArt({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: Stack(alignment: Alignment.center, children: <Widget>[
        const NeonBox(
          glow: true,
          radius: 26,
          padding: EdgeInsets.all(30),
          child: AnimeBoxCube(size: 76),
        ),
        const Positioned(
          top: 6,
          right: 8,
          child: QualityBadge(VideoQuality.fhd),
        ),
        const Positioned(
          bottom: 14,
          left: 8,
          child: QualityBadge(VideoQuality.hd),
        ),
        const Positioned(
          top: 24,
          left: 10,
          child: _MiniTile(icon: Icons.play_arrow_rounded),
        ),
        const Positioned(
          bottom: 44,
          right: 10,
          child: _MiniTile(icon: Icons.favorite_rounded),
        ),
      ]),
    );
  }
}

class _MiniTile extends StatelessWidget {
  const _MiniTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, size: 18, color: AppColors.primaryBright),
    );
  }
}

/// Illustration de l'écran 3 : pastille Telegram + anneau « bouclier » —
/// icôographie existante du projet (TelegramLogo vectoriel).
class OnboardingPrivacyArt extends StatelessWidget {
  const OnboardingPrivacyArt({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 198,
      child: Stack(alignment: Alignment.center, children: <Widget>[
        Container(
          width: 178,
          height: 178,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
          ),
        ),
        Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
        ),
        const TelegramLogo(size: 78),
        const Positioned(
          top: 8,
          right: 16,
          child: _MiniTile(icon: Icons.lock_rounded),
        ),
        const Positioned(
          bottom: 8,
          left: 16,
          child: _MiniTile(icon: Icons.shield_rounded),
        ),
      ]),
    );
  }
}
