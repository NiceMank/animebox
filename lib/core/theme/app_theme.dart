import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Thèmes globaux de l'application (typographie, composants Material) :
/// - [AppTheme.dark] : identité sombre bleue (défaut) ;
/// - [AppTheme.light] : vrai mode clair (§6/§19) — fonds clairs, texte
///   sombre, bleu en accent.
///
/// Chaque getter lit sa palette de RÉFÉRENCE immuable (AppColorsDark /
/// AppColorsLight) ; les widgets lisent quant à eux les champs actifs de
/// [AppColors], permutés par [AppColors.apply].
abstract final class AppTheme {
  /// Thème SOMBRE (bleu nuit — identité par défaut).
  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: AppColorsDark.background,
        surface: AppColorsDark.surface,
        surfaceAlt: AppColorsDark.surfaceAlt,
        primary: AppColorsDark.primary,
        primaryBright: AppColorsDark.primaryBright,
        textPrimary: AppColorsDark.textPrimary,
        textSecondary: AppColorsDark.textSecondary,
        divider: AppColorsDark.divider,
        danger: AppColorsDark.danger,
      );

  /// Thème CLAIR (fonds clairs, texte sombre, bleu en accent).
  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: AppColorsLight.background,
        surface: AppColorsLight.surface,
        surfaceAlt: AppColorsLight.surfaceAlt,
        primary: AppColorsLight.primary,
        primaryBright: AppColorsLight.primaryBright,
        textPrimary: AppColorsLight.textPrimary,
        textSecondary: AppColorsLight.textSecondary,
        divider: AppColorsLight.divider,
        danger: AppColorsLight.danger,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceAlt,
    required Color primary,
    required Color primaryBright,
    required Color textPrimary,
    required Color textSecondary,
    required Color divider,
    required Color danger,
  }) {
    final ColorScheme colorScheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: primary,
            onPrimary: Colors.white,
            secondary: primaryBright,
            onSecondary: background,
            surface: surface,
            onSurface: textPrimary,
            error: danger,
            outline: divider,
          )
        : ColorScheme.light(
            primary: primary,
            onPrimary: Colors.white,
            secondary: primaryBright,
            onSecondary: Colors.white,
            surface: surface,
            onSurface: textPrimary,
            error: danger,
            outline: divider,
          );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Poppins',
    );

    return base.copyWith(
      // La famille est appliquée explicitement au textTheme (copyWith
      // remplace le textTheme de base sans hériter de fontFamily).
      textTheme: _textTheme(textPrimary: textPrimary, textSecondary: textSecondary).apply(fontFamily: 'Poppins'),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: textPrimary,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceAlt,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceAlt,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
    );
  }

  /// Typographie identique dans les deux thèmes (seules les couleurs
  /// de texte changent).
  static TextTheme _textTheme({required Color textPrimary, required Color textSecondary}) {
    return TextTheme(
      displaySmall: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.5, height: 1.15),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary, height: 1.25),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary, height: 1.25),
      titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
      titleSmall: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: textPrimary),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: textPrimary, height: 1.45),
      bodyMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: textSecondary, height: 1.4),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: textSecondary),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: 0.2),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: 0.2),
      labelSmall: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: textSecondary, letterSpacing: 0.4),
    );
  }
}
