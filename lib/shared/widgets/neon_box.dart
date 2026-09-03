import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Conteneur avec bordure et lueur bleues (élément décoratif réutilisable — couleurs actives via AppColors).
class NeonBox extends StatelessWidget {
  const NeonBox({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(14),
    this.glow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final Color border = AppColors.primary.withValues(alpha: 0.35);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: glow
            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, 8))]
            : null,
      ),
      child: child,
    );
  }
}
