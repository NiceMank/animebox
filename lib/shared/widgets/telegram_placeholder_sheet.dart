import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'primary_button.dart';

/// Feuille d'information « Telegram à venir » — utilisée par les boutons
/// « Ouvrir dans Telegram » (aucun vrai lien à ce stade).
class TelegramPlaceholderSheet {
  const TelegramPlaceholderSheet._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: AppColors.primaryGradient),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 24)],
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 16),
              const Text(
                'Connexion Telegram',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Le lien Telegram sera connecté dans une prochaine étape.\n'
                'Vous pourrez alors ouvrir directement la publication source.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Compris',
                expanded: false,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
