import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formats.dart';
import '../../features/telegram/data/models/telegram_source.dart';
import 'source_status_indicator.dart';

/// Carte d'une source Telegram (liste « Mes sources »).
class TelegramSourceCard extends StatelessWidget {
  const TelegramSourceCard({
    super.key,
    required this.source,
    required this.onTap,
    this.onSettingsTap,
    this.compact = false,
  });

  final TelegramSource source;
  final VoidCallback onTap;

  /// Bouton « paramètres » (peut être masqué dans les écrans compacts).
  final VoidCallback? onSettingsTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(source: source),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text('@${source.username}', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                  if (onSettingsTap != null)
                    IconButton(
                      tooltip: 'Paramètres de la source',
                      onPressed: onSettingsTap,
                      icon: Icon(Icons.settings_outlined, size: 20, color: AppColors.textMuted),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SourceStatusIndicator(status: source.status),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      source.lastSync == null
                          ? 'Jamais synchronisée'
                          : 'Dernière synchro : ${formatRelativeTime(source.lastSync!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              if (!compact && source.analyzedPosts > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MiniStat(label: 'publications', value: formatCount(source.analyzedPosts)),
                    const SizedBox(width: 16),
                    _MiniStat(label: 'animés', value: formatCount(source.detectedAnime)),
                    const SizedBox(width: 16),
                    _MiniStat(label: 'épisodes', value: formatCount(source.detectedEpisodes)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.source});

  final TelegramSource source;

  @override
  Widget build(BuildContext context) {
    final Widget content = source.avatarAsset != null
        ? Image.asset(
            source.avatarAsset!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _initials(source.name),
          )
        : _initials(source.name);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: 46, height: 46, child: content),
    );
  }

  Widget _initials(String name) {
    final String initials = name.trim().isEmpty ? '?' : name.trim().split(' ').map((word) => word[0]).take(2).join().toUpperCase();
    return Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: Text(initials, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryBright)),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 1),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
