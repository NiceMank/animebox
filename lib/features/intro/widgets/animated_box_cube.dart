import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Cube AnimeBox animé — rotation 3D continue (lacet + tangage),
/// projection perspective, couleurs LUES DANS LA PALETTE ACTIVE
/// (sombre/clair via [AppColors]). Réutilisé par l'écran d'accueil.
class AnimatedBoxCube extends StatelessWidget {
  const AnimatedBoxCube({super.key, this.size = 150, this.period = const Duration(seconds: 7)});

  /// Côté de la zone de dessin (le cube y tient toujours entièrement).
  final double size;

  /// Durée d'un tour complet.
  final Duration period;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: _SpinningCube(period: period),
    );
  }
}

class _SpinningCube extends StatefulWidget {
  const _SpinningCube({required this.period});

  final Duration period;

  @override
  State<_SpinningCube> createState() => _SpinningCubeState();
}

class _SpinningCubeState extends State<_SpinningCube> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) =>
          CustomPaint(painter: _CubePainter(t: _controller.value)),
    );
  }
}

class _CubePainter extends CustomPainter {
  _CubePainter({required this.t});

  /// Progression du cycle (0 → 1), répétée.
  final double t;

  // Sommets du cube unité (côté 2, centré sur l'origine).
  static const List<List<double>> _vertices = [
    [-1, -1, -1],
    [1, -1, -1],
    [1, 1, -1],
    [-1, 1, -1],
    [-1, -1, 1],
    [1, -1, 1],
    [1, 1, 1],
    [-1, 1, 1],
  ];

  // Faces (indices des sommets, ordonnées) avec leur identité de couleur :
  // 0 = bleu primaire, 1 = bleu sombre, 2 = bleu lumineux.
  static const List<(List<int>, int)> _faces = [
    ([0, 1, 2, 3], 1), // face arrière
    ([4, 5, 6, 7], 0), // face avant
    ([0, 3, 7, 4], 2), // gauche
    ([1, 2, 6, 5], 1), // droite
    ([3, 2, 6, 7], 2), // haut
    ([0, 1, 5, 4], 1), // bas
  ];

  static const double _perspective = 3.6;

  List<Offset> _project({required double yaw, required double pitch, required double scale}) {
    final double cy = math.cos(yaw);
    final double sy = math.sin(yaw);
    final double cx = math.cos(pitch);
    final double sx = math.sin(pitch);
    return [
      for (final List<double> v in _vertices)
        () {
          // Rotation Y (lacet).
          final double x1 = v[0] * cy + v[2] * sy;
          final double z1 = -v[0] * sy + v[2] * cy;
          // Rotation X (tangage).
          final double y2 = v[1] * cx - z1 * sx;
          final double z2 = v[1] * sx + z1 * cx;
          // Projection perspective simple.
          final double f = _perspective / (_perspective - z2 * 0.55);
          return Offset(x1 * f * scale, y2 * f * scale);
        }()
    ];
  }

  double _faceDepth(List<int> face, {required double yaw, required double pitch}) {
    final double cy = math.cos(yaw);
    final double sy = math.sin(yaw);
    final double cx = math.cos(pitch);
    final double sx = math.sin(pitch);
    double sum = 0;
    for (final int i in face) {
      final List<double> v = _vertices[i];
      final double z1 = -v[0] * sy + v[2] * cy;
      sum += v[1] * sx + z1 * cx;
    }
    return sum;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double yaw = 2 * math.pi * t + 0.5;
    final double pitch = 0.42 + 0.14 * math.sin(2 * math.pi * t);
    final double bob = 0.06 * size.height * math.sin(2 * math.pi * t * 2 + 1.2);
    final double scale = size.width * 0.185;

    final List<Offset> pts = _project(yaw: yaw, pitch: pitch, scale: scale);
    canvas.translate(size.width / 2, size.height * 0.52 + bob);

    // Lueur d'ombre au sol (ellipse douce — suit la flottaison).
    final Paint shadow = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawOval(Rect.fromCenter(center: Offset(0, size.height * 0.34), width: size.width * 0.52, height: size.height * 0.1), shadow);

    final Map<int, Color> fills = {
      0: AppColors.primary.withValues(alpha: 0.92),
      1: AppColors.primaryDark.withValues(alpha: 0.92),
      2: AppColors.primaryBright.withValues(alpha: 0.92),
    };
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.primaryBright.withValues(alpha: 0.75);

    // Peinture arrière → avant (tri par profondeur moyenne).
    final List<(List<int>, int)> ordered = List.of(_faces)
      ..sort((a, b) => _faceDepth(a.$1, yaw: yaw, pitch: pitch).compareTo(_faceDepth(b.$1, yaw: yaw, pitch: pitch)));

    for (final (List<int> face, int kind) in ordered) {
      final Path path = Path()..addPolygon([for (final int i in face) pts[i]], true);
      canvas.drawPath(path, Paint()..color = fills[kind]!);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(_CubePainter oldDelegate) => oldDelegate.t != t;
}
