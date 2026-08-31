import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/anime/data/models/season.dart';

/// Sélecteur de saisons horizontal (Saison 2 · Saison 1 · Spéciaux…).
///
/// [specialsCount] permet d'ajouter un onglet « Spéciaux ».
class SeasonSelector extends StatelessWidget {
  const SeasonSelector({
    super.key,
    required this.seasons,
    required this.selectedId,
    required this.onSelected,
    this.showSpecials = false,
    this.specialsCount = 0,
    this.specialsSelected = false,
  });

  final List<Season> seasons;

  /// Id de la saison sélectionnée (null si « Spéciaux » actif).
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final bool showSpecials;
  final int specialsCount;
  final bool specialsSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: seasons.length + (showSpecials ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int index) {
          if (index < seasons.length) {
            final Season season = seasons[index];
            final bool selected = season.id == selectedId && !specialsSelected;
            return _SeasonChip(
              label: 'Saison ${season.number}',
              count: season.episodeCount,
              selected: selected,
              onTap: () => onSelected(season.id),
            );
          }
          return _SeasonChip(
            label: 'Spéciaux',
            count: specialsCount,
            selected: specialsSelected,
            onTap: () => onSelected(null),
          );
        },
      ),
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? const LinearGradient(colors: AppColors.primaryGradient) : null,
          color: selected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Colors.transparent : AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.22) : AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.primaryBright,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
