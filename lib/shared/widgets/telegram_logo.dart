import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Véritable pictogramme Telegram (avion en papier dans une pastille),
/// dessiné en vectoriel — aucune icône emoji.
///
/// Utilisé sur l'écran de connexion, les avatars de sources et les
/// boutons « Ouvrir dans Telegram ».
class TelegramLogo extends StatelessWidget {
  const TelegramLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Telegram',
      child: CustomPaint(
        size: Size.square(size),
        painter: _TelegramLogoPainter(),
      ),
    );
  }
}

class _TelegramLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Rect circle = Offset.zero & size;
    final Paint background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primaryBright, AppColors.primary],
      ).createShader(circle);
    canvas.drawCircle(circle.center, size.width / 2, background);

    // Plan du pictogramme Telegram (forme classique du logo).
    final double s = size.width / 24;
    final Path plane = Path()
      ..moveTo(3.1 * s, 12.3 * s)
      ..lineTo(21.2 * s, 4.6 * s)
      ..lineTo(10.6 * s, 13.4 * s)
      ..lineTo(10.6 * s, 20.3 * s)
      ..lineTo(14.3 * s, 16.0 * s)
      ..lineTo(18.4 * s, 19.4 * s)
      ..close();
    canvas.drawPath(plane, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
