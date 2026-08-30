import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'primary_button.dart';

/// État vide générique (icône, titre, message, action optionnelle).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.18), blurRadius: 28)],
              ),
              child: Icon(icon, size: 34, color: AppColors.primaryBright),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              PrimaryButton(label: actionLabel!, icon: Icons.arrow_forward_rounded, onTap: onAction, expanded: false),
            ],
          ],
        ),
      ),
    );
  }
}
