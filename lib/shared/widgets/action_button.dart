import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Bouton d'action carré du lecteur (favori, télécharger, épisodes…).
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// État actif (ex. favori déjà coché) — cœur plein.
  final bool active;

  /// Accent bleu fort (action principale).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final Color color = active
        ? AppColors.danger
        : highlight
            ? AppColors.primaryBright
            : AppColors.textPrimary;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: highlight ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active ? AppColors.danger.withValues(alpha: 0.4) : AppColors.divider,
                ),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
