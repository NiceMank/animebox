import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formats.dart';
import '../../features/telegram/data/models/sync_history_entry.dart';

/// Ligne d'entrée de l'historique de synchronisation.
class SyncHistoryTile extends StatelessWidget {
  const SyncHistoryTile({super.key, required this.entry, this.onTap});

  final SyncHistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool success = entry.success;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (success ? AppColors.success : AppColors.danger).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  success ? Icons.check_rounded : Icons.error_outline_rounded,
                  size: 19,
                  color: success ? AppColors.success : AppColors.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatCount(entry.analyzedPosts)} publications · ${formatRelativeTime(entry.date)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 19, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
