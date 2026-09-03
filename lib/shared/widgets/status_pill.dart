import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Pastille d'état générique (langue, disponibilité, nouveauté…).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color, this.filled = false});

  /// Pastille colorée selon la langue (`VF`, `VOSTFR`…).
  factory StatusPill.language(String label) => StatusPill(
        label,
        color: label.toUpperCase() == 'VF' ? AppColors.vf : AppColors.vostfr,
      );

  final String label;
  final Color? color;

  /// Remplissage plein (utilisé pour « Nouvel épisode »).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final Color tone = color ?? AppColors.primaryBright;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: filled ? LinearGradient(colors: AppColors.accentGradient) : null,
        color: filled ? null : tone.withValues(alpha: 0.14),
        border: Border.all(color: filled ? Colors.transparent : tone.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: filled ? Colors.white : tone,
        ),
      ),
    );
  }
}
