import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Bouton cœur de favori (état contrôlé par le parent).
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.isFavorite, required this.onTap});

  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isFavorite ? AppColors.danger.withValues(alpha: 0.45) : AppColors.divider),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (Widget child, Animation<double> animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey<bool>(isFavorite),
            size: 22,
            color: isFavorite ? AppColors.danger : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
