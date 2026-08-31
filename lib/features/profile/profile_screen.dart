import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../app/router.dart';
import '../telegram/data/services/telegram_service.dart';
import '../telegram/data/models/telegram_user.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/status_pill.dart';

/// Écran Profil — état de la connexion Telegram, accès aux sources et à
/// la synchronisation, réglages de l'application.
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
        final TelegramService service = telegramService;
        final int sourceCount = service.sources.length;
        final int activeCount = service.sources.where((s) => s.syncEnabled).length;
        final TelegramUser? user = service.currentUser;

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
                      child: Center(
                        child: service.authState == TelegramAuthState.connected && user != null
                            ? Text(user.initials, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white))
                            : const Icon(Icons.person_rounded, size: 44, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      service.authState == TelegramAuthState.connected && user != null ? user.fullName : 'Invité',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      service.authState == TelegramAuthState.connected && user?.username != null
                          ? '@${user!.username}'
                          : 'Connectez Telegram pour synchroniser vos chaînes d\'animés.',
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
                title: 'Connexion Telegram',
                subtitle: _connectionSubtitle(service),
                badge: _connectionBadge(service),
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.telegramConnect),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                icon: Icons.storage_rounded,
                title: 'Mode de données',
                subtitle: service.isBackendApi
                    ? 'API : ${service.apiBaseUrl}'
                    : 'Données locales de démonstration',
                onTap: () => _showDataModeInfo(context, service),
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

  String _connectionSubtitle(TelegramService service) => switch (service.authState) {
        TelegramAuthState.connected =>
          'Connecté — ${service.currentUser?.fullName ?? 'compte Telegram'}',
        TelegramAuthState.connecting => 'Connexion en cours…',
        TelegramAuthState.expired => 'Session expirée — reconnectez-vous',
        TelegramAuthState.error => 'Erreur — appuyez pour réessayer',
        TelegramAuthState.disconnected => 'Connectez votre compte Telegram',
      };

  String? _connectionBadge(TelegramService service) => switch (service.authState) {
        TelegramAuthState.connected => 'Connecté',
        TelegramAuthState.connecting => '…',
        TelegramAuthState.expired => 'Expirée',
        _ => null,
      };

  void _showDataModeInfo(BuildContext context, TelegramService service) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.storage_rounded, size: 22, color: AppColors.primaryBright),
                  SizedBox(width: 10),
                  Text('Mode de données', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                service.isBackendApi
                    ? 'Cette application utilise le backend API AnimeBox.\n\nAdresse : ${service.apiBaseUrl}\n\nLes secrets Telegram restent côté serveur ; aucune donnée sensible n\'est stockée sur cet appareil.'
                    : 'Cette application utilise les données locales de démonstration (mode simulation).\n\nPour utiliser le vrai service Telegram, lancez le backend et l\'application avec :\n\nflutter run --dart-define=ANIMEBOX_API_URL=http://IP_DU_BACKEND:8000',
                style: const TextStyle(fontSize: 13, height: 1.55, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Center(
                child: PrimaryButton(
                  label: 'Fermer',
                  expanded: false,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
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
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
              if (badge != null)
                StatusPill(
                  badge!,
                  color: badge == 'Connecté' ? AppColors.success : AppColors.primaryBright,
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
