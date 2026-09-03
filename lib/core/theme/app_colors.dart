import 'package:flutter/material.dart';

/// Palette visuelle AnimeBox — SOURCE DE VÉRITÉ UNIQUE des couleurs (§3/§18).
///
/// L'identité violette est remplacée par une identité BLEUE professionnelle,
/// en deux variantes :
/// - [AppColorsDark] : thème sombre — fond noir-bleu profond, surfaces
///   légèrement bleutées, accent bleu lumineux utilisé avec parcimonie
///   (bouton principal, sélection, icône active, progression, lien, focus,
///   interrupteur/curseur actif) — jamais de gros aplats bleus ;
/// - [AppColorsLight] : vrai thème clair — fonds blancs/gris très clair,
///   texte sombre, bleu en accent.
///
/// Les widgets lisent les champs statiques de [AppColors] ; [AppColors.apply]
/// (appelé une fois par la racine `AnimeBoxApp`) bascule intégralement la
/// palette active. Aucune couleur d'interface ne doit être codée en dur
/// ailleurs : si le bleu change demain, ce fichier est le SEUL à toucher.
///
/// Sémantique figée dans les deux thèmes (§4) : succès = vert,
/// avertissement = ambre/orange, erreur = rouge — jamais bleuisés.
/// Les pastilles de langue (VF/VOSTFR) restent des couleurs de CONTENU.

/// Palette du mode SOMBRE (référence immuable).
abstract final class AppColorsDark {
  // Fonds — noir-bleu profond, surfaces légèrement bleutées.
  static const Color background = Color(0xFF0A1020);
  static const Color surface = Color(0xFF131B2E);
  static const Color surfaceAlt = Color(0xFF1A2438);
  static const Color card = Color(0xFF141D31);
  static const Color bottomBar = Color(0xFF0C1424);

  // Accents bleus (bleu primaire, sombre, lumineux).
  static const Color primary = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryBright = Color(0xFF93C5FD);

  // Texte.
  static const Color textPrimary = Color(0xFFF2F6FD);
  static const Color textSecondary = Color(0xFFA4B0CC);
  static const Color textMuted = Color(0xFF6B7793);

  // Utilitaires & sémantique (vert / ambre / rouge — sens conservé, §4).
  static const Color divider = Color(0xFF25354F);
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFEF4444);

  /// Pastilles de langue — couleurs de contenu conservées.
  static const Color vf = Color(0xFFFB7185); // VF — rose
  static const Color vostfr = Color(0xFF38BDF8); // VOSTFR — bleu ciel

  // Dégradés bleus (l'ancien magenta disparaît).
  static const List<Color> primaryGradient = [primaryDark, primary];
  static const List<Color> accentGradient = [primary, vostfr];
}

/// Palette du mode CLAIR (référence immuable).
abstract final class AppColorsLight {
  // Fonds — blanc / gris bleuté très clair.
  static const Color background = Color(0xFFF7F9FD);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF0F4FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color bottomBar = Color(0xFFFFFFFF);

  // Accents bleus (lisibles sur fond clair).
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryBright = Color(0xFF1E40AF);

  // Texte — sombre, bien contrasté.
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF475467);
  static const Color textMuted = Color(0xFF98A2B3);

  // Utilitaires & sémantique (vert / ambre / rouge — sens conservé, §4).
  static const Color divider = Color(0xFFE2E8F2);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);

  /// Pastilles de langue — contenu (teintes rehaussées pour le blanc).
  static const Color vf = Color(0xFFE11D48); // VF — rose
  static const Color vostfr = Color(0xFF0284C7); // VOSTFR — bleu

  // Dégradés bleus.
  static const List<Color> primaryGradient = [primaryDark, primary];
  static const List<Color> accentGradient = [primary, vostfr];
}

/// Palette ACTIVE de l'application (mode sombre par défaut).
///
/// Noms de champs stables : les écrans, widgets et composants n'ont pas à
/// connaître le thème courant — ils lisent `AppColors.xxx`, et [apply]
/// permute tout d'un seul coup lors d'un changement de thème.
abstract final class AppColors {
  /// Luminosité actuellement appliquée (garde-fou utile aux tests).
  static Brightness activeBrightness = Brightness.dark;

  // Fonds.
  static Color background = AppColorsDark.background;
  static Color surface = AppColorsDark.surface;
  static Color surfaceAlt = AppColorsDark.surfaceAlt;
  static Color card = AppColorsDark.card;
  static Color bottomBar = AppColorsDark.bottomBar;

  // Accents bleus.
  static Color primary = AppColorsDark.primary;
  static Color primaryDark = AppColorsDark.primaryDark;
  static Color primaryBright = AppColorsDark.primaryBright;

  // Texte.
  static Color textPrimary = AppColorsDark.textPrimary;
  static Color textSecondary = AppColorsDark.textSecondary;
  static Color textMuted = AppColorsDark.textMuted;

  // Utilitaires & sémantique.
  static Color divider = AppColorsDark.divider;
  static Color success = AppColorsDark.success;
  static Color warning = AppColorsDark.warning;
  static Color danger = AppColorsDark.danger;

  /// Couleurs des pastilles de langue.
  static Color vf = AppColorsDark.vf; // VF — rose
  static Color vostfr = AppColorsDark.vostfr; // VOSTFR — bleu

  // Dégradés.
  static List<Color> primaryGradient = AppColorsDark.primaryGradient;
  static List<Color> accentGradient = AppColorsDark.accentGradient;

  /// Bascule TOUTES les couleurs actives vers la palette demandée —
  /// point d'entrée unique du changement de thème (§3).
  static void apply(Brightness brightness) {
    activeBrightness = brightness;
    final bool light = brightness == Brightness.light;

    background = light ? AppColorsLight.background : AppColorsDark.background;
    surface = light ? AppColorsLight.surface : AppColorsDark.surface;
    surfaceAlt = light ? AppColorsLight.surfaceAlt : AppColorsDark.surfaceAlt;
    card = light ? AppColorsLight.card : AppColorsDark.card;
    bottomBar = light ? AppColorsLight.bottomBar : AppColorsDark.bottomBar;

    primary = light ? AppColorsLight.primary : AppColorsDark.primary;
    primaryDark = light ? AppColorsLight.primaryDark : AppColorsDark.primaryDark;
    primaryBright = light ? AppColorsLight.primaryBright : AppColorsDark.primaryBright;

    textPrimary = light ? AppColorsLight.textPrimary : AppColorsDark.textPrimary;
    textSecondary = light ? AppColorsLight.textSecondary : AppColorsDark.textSecondary;
    textMuted = light ? AppColorsLight.textMuted : AppColorsDark.textMuted;

    divider = light ? AppColorsLight.divider : AppColorsDark.divider;
    success = light ? AppColorsLight.success : AppColorsDark.success;
    warning = light ? AppColorsLight.warning : AppColorsDark.warning;
    danger = light ? AppColorsLight.danger : AppColorsDark.danger;

    vf = light ? AppColorsLight.vf : AppColorsDark.vf;
    vostfr = light ? AppColorsLight.vostfr : AppColorsDark.vostfr;

    primaryGradient = light ? AppColorsLight.primaryGradient : AppColorsDark.primaryGradient;
    accentGradient = light ? AppColorsLight.accentGradient : AppColorsDark.accentGradient;
  }
}
