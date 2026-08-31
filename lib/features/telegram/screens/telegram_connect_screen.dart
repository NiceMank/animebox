import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/telegram_logo.dart';
import '../data/models/api_exception.dart';
import '../data/models/telegram_user.dart';
import '../data/services/telegram_service.dart';

/// Écran « Connecter Telegram » : flux de connexion complet avec états
/// (non connecté, connexion en cours, connecté, session expirée, erreur).
///
/// Le numéro est envoyé au backend, qui gère la vraie connexion Telegram
/// côté serveur ; l'application ne manipule aucun secret.
class TelegramConnectScreen extends StatefulWidget {
  const TelegramConnectScreen({super.key, required this.service});

  final TelegramService service;

  @override
  State<TelegramConnectScreen> createState() => _TelegramConnectScreenState();
}

enum _Stage { intro, phone, code }

class _TelegramConnectScreenState extends State<TelegramConnectScreen> {
  _Stage _stage = _Stage.intro;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _busy = false;
  String? _inlineError;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      await widget.service.requestCode(_phoneController.text.trim());
      setState(() => _stage = _Stage.code);
    } on ApiException catch (error) {
      setState(() => _inlineError = error.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      await widget.service.verifyCode(_phoneController.text.trim(), _codeController.text.trim());
      // L'état `connected` est porté par le service ; l'interface réagit.
    } on ApiException catch (error) {
      setState(() => _inlineError = error.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Se déconnecter ?', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: const Text(
          'Vos sources resteront enregistrées, mais la synchronisation sera interrompue jusqu\'à la prochaine connexion.',
          style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Se déconnecter', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.service.disconnect();
      if (mounted) setState(() => _stage = _Stage.intro);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (BuildContext context, Widget? child) {
        final TelegramService service = widget.service;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('Connexion Telegram', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          ),
          body: switch (service.authState) {
            TelegramAuthState.connected => _AccountView(service: service, onDisconnect: _disconnect),
            TelegramAuthState.expired => _ExpiredView(onReconnect: () => setState(() => _stage = _Stage.phone)),
            _ => _buildForm(service),
          },
        );
      },
    );
  }

  Widget _buildForm(TelegramService service) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      children: [
        if (_stage == _Stage.intro) ...[
          const SizedBox(height: 18),
          const Center(child: TelegramLogo(size: 86)),
          const SizedBox(height: 22),
          const Text(
            'Connectez Telegram',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          const Text(
            'Connectez votre compte Telegram pour permettre à AnimeBox d\'accéder aux sources que vous choisissez.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.55, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 22),
          const _InfoRow(icon: Icons.lock_outline_rounded, text: 'Votre numéro et votre session restent protégés côté serveur.'),
          const SizedBox(height: 10),
          const _InfoRow(icon: Icons.visibility_outlined, text: 'Seuls les canaux que vous ajoutez sont consultés.'),
          const SizedBox(height: 10),
          const _InfoRow(icon: Icons.phonelink_lock_rounded, text: 'Aucun secret n\'est stocké sur votre appareil.'),
          const SizedBox(height: 26),
          PrimaryButton(
            label: 'Connecter Telegram',
            icon: Icons.send_rounded,
            onTap: () => setState(() => _stage = _Stage.phone),
          ),
        ],
        if (_stage == _Stage.phone) ...[
          const SizedBox(height: 8),
          const Text(
            'Votre numéro de téléphone',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Un code de connexion vous sera envoyé via Telegram.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            cursorColor: AppColors.primary,
            decoration: _fieldDecoration('+229 01 23 45 67', Icons.phone_outlined),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: _busy ? 'Envoi en cours…' : 'Envoyer le code',
            icon: Icons.send_rounded,
            onTap: _busy ? null : _sendCode,
          ),
        ],
        if (_stage == _Stage.code) ...[
          const SizedBox(height: 8),
          const Text(
            'Code de connexion',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Saisissez le code reçu dans Telegram.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 5,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, letterSpacing: 6),
            cursorColor: AppColors.primary,
            decoration: _fieldDecoration('• • • • •', Icons.pin_outlined).copyWith(counterText: ''),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: _busy ? 'Vérification…' : 'Vérifier',
            icon: Icons.verified_outlined,
            onTap: _busy ? null : _verifyCode,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _sendCode,
              child: const Text('Renvoyer le code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryBright)),
            ),
          ),
        ],
        if (_inlineError != null) ...[
          const SizedBox(height: 16),
          _ErrorBox(message: _inlineError!),
        ],
        if (service.authState == TelegramAuthState.error && service.authError != null && _inlineError == null) ...[
          const SizedBox(height: 16),
          _ErrorBox(message: service.authError!, onRetry: service.refreshSession),
        ],
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.primaryBright, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.primaryBright),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 19, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textPrimary)),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Réessayer', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryBright)),
            ),
        ],
      ),
    );
  }
}

/// Vue « connecté » : informations publiques du compte.
class _AccountView extends StatelessWidget {
  const _AccountView({required this.service, required this.onDisconnect});

  final TelegramService service;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final TelegramUser user = service.currentUser!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              _Avatar(user: user),
              const SizedBox(height: 14),
              Text(user.fullName, style: Theme.of(context).textTheme.titleLarge),
              if (user.username != null) ...[
                const SizedBox(height: 3),
                Text('@${user.username}', style: Theme.of(context).textTheme.bodySmall),
              ],
              if (user.phone != null) ...[
                const SizedBox(height: 3),
                Text(user.phone!, style: Theme.of(context).textTheme.labelSmall),
              ],
              const SizedBox(height: 12),
              const StatusPill('Connecté', color: AppColors.success),
              const SizedBox(height: 14),
              const Text(
                'Telegram connecté',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        PrimaryButton(
          label: 'Rafraîchir la session',
          icon: Icons.refresh_rounded,
          outlined: true,
          onTap: () async {
            await service.refreshSession();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Session vérifiée.')),
              );
            }
          },
        ),
        const SizedBox(height: 10),
        PrimaryButton(
          label: 'Se déconnecter',
          icon: Icons.logout_rounded,
          outlined: true,
          onTap: onDisconnect,
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final TelegramUser user;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: AppColors.primaryGradient),
      ),
      child: Text(user.initials, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
    );

    final String? photo = user.photoUrl;
    if (photo == null || photo.isEmpty) {
      return SizedBox(width: 74, height: 74, child: ClipOval(child: fallback));
    }
    return SizedBox(
      width: 74,
      height: 74,
      child: ClipOval(
        child: Image.network(
          photo,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

/// État « session expirée ».
class _ExpiredView extends StatelessWidget {
  const _ExpiredView({required this.onReconnect});

  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.danger.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.timer_off_outlined, size: 34, color: AppColors.danger),
            ),
            const SizedBox(height: 18),
            const Text(
              'Session expirée',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Votre connexion Telegram a expiré. Reconnectez-vous pour continuer à utiliser vos sources.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              label: 'Se reconnecter',
              icon: Icons.login_rounded,
              onTap: onReconnect,
            ),
          ],
        ),
      ),
    );
  }
}
