import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Thème sombre global de l'application (typographie, composants Material).
abstract final class AppTheme {
  static ThemeData get dark {
    const ColorScheme colorScheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primaryBright,
      onSecondary: AppColors.background,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      outline: AppColors.divider,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Poppins',
    );

    return base.copyWith(
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5, height: 1.15),
        headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25),
        headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25),
        titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        titleSmall: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.45),
        bodyMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.4),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: 0.2),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: 0.2),
        labelSmall: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0.4),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textPrimary,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
    );
  }
}
