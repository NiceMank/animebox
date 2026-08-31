import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../app/router.dart';
import '../telegram/data/services/telegram_service.dart';
import '../../shared/widgets/status_pill.dart';

/// Écran Profil — placeholder global avec accès aux sources Telegram
/// et à la synchronisation (connexion Telegram prévue plus tard).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.telegramService});

  final TelegramService telegramService;

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature : disponible dans une prochaine étape.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: telegramService,
      builder: (BuildContext context, Widget? child) {
        final int sourceCount = telegramService.sources.length;
        final int activeCount = telegramService.sources.where((s) => s.syncEnabled).length;

        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              Text('Profil', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: AppColors.primaryGradient),
                        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 10))],
                      ),
                      child: const Icon(Icons.person_rounded, size: 44, color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    Text('Invité', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Connectez Telegram pour synchroniser vos chaînes d\'animés.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _MenuCard(
                icon: Icons.rss_feed_rounded,
                title: 'Mes sources Telegram',
                subtitle: sourceCount == 0 ? 'Aucune source — ajoutez un canal' : '$sourceCount source(s) · $activeCount active(s)',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.sources),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                icon: Icons.sync_rounded,
                title: 'Synchronisation',
                subtitle: 'État du moteur, statistiques et historique',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.sync),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                icon: Icons.send_rounded,
                title: 'Connecter Telegram',
                subtitle: 'Synchronisez vos chaînes d\'animés',
                badge: 'Bientôt',
                onTap: () => _comingSoon(context, 'Connexion Telegram'),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'Soyez alerté des nouveaux épisodes',
                badge: 'Bientôt',
                onTap: () => _comingSoon(context, 'Notifications'),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                icon: Icons.settings_rounded,
                title: 'Paramètres',
                subtitle: 'Application, lecteur, stockage',
                badge: 'Bientôt',
                onTap: () => _comingSoon(context, 'Paramètres'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.primaryBright, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
              if (badge != null) StatusPill(badge!, color: AppColors.primaryBright),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
