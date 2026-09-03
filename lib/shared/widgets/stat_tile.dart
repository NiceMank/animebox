import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Tuile de statistique (écran Synchronisation).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent = false,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Accent bleu (valeur mise en avant).
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: accent ? AppColors.primaryBright : AppColors.textMuted),
              const SizedBox(height: 8),
            ],
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: accent ? AppColors.primaryBright : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
