import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Option de langue / sous-titres sélectionnable.
class LanguageOption extends StatelessWidget {
  const LanguageOption({
    super.key,
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// Précision affichée sous le libellé (ex. « Français »).
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.16) : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary.withValues(alpha: 0.75) : AppColors.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 17,
                color: selected ? AppColors.primaryBright : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.primaryBright : AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
