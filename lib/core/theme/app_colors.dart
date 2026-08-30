import 'package:flutter/material.dart';

/// Palette globale : fond noir/violet très sombre, accents violet lumineux.
abstract final class AppColors {
  // Fonds.
  static const Color background = Color(0xFF0A0817);
  static const Color surface = Color(0xFF16122C);
  static const Color surfaceAlt = Color(0xFF1C1734);
  static const Color card = Color(0xFF151130);
  static const Color bottomBar = Color(0xFF100C22);

  // Accents violets.
  static const Color primary = Color(0xFF8B5CF6);
  static const Color primaryDark = Color(0xFF6C3AE8);
  static const Color primaryBright = Color(0xFFB9A4FF);

  // Texte.
  static const Color textPrimary = Color(0xFFF4F2FD);
  static const Color textSecondary = Color(0xFFA6A1C2);
  static const Color textMuted = Color(0xFF6E6990);

  // Utilitaires.
  static const Color divider = Color(0xFF262142);
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFB7185);

  /// Couleurs des pastilles de langue.
  static const Color vf = Color(0xFFFB7185); // VF — rose
  static const Color vostfr = Color(0xFF38BDF8); // VOSTFR — bleu

  // Dégradés.
  static const List<Color> primaryGradient = [primaryDark, primary];
  static const List<Color> accentGradient = [primary, Color(0xFFD946EF)];
}
