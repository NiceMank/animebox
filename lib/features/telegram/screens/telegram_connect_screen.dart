import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/telegram_logo.dart';
import '../data/models/api_exception.dart';
import '../data/models/telegram_user.dart';
import '../data/services/telegram_service.dart';

/// Écran « Connecter Telegram » : véritable processus de connexion.
///
/// États gérés : non connecté, connexion en cours, code requis, mot de
/// passe 2FA requis, connecté, session expirée, erreur. La connexion est
/// effectuée DIRECTEMENT entre l'appareil et Telegram (TDLib) : aucun
/// serveur intermédiaire, aucun secret dans l'application.
class TelegramConnectScreen extends StatefulWidget {
  const TelegramConnectScreen({super.key, required this.service});

  final TelegramService service;

  @override
  State<TelegramConnectScreen> createState() => _TelegramConnectScreenState();
}

enum _Stage { intro, phone }

class _TelegramConnectScreenState extends State<TelegramConnectScreen> {
  _Stage _stage = _Stage.intro;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _busy = false;
  String? _inlineError;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      await widget.service.requestCode(_phoneController.text.trim());
      // L'état `codeRequired` arrive via le service : l'interface réagit.
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
      // `connected` ou `passwordRequired` : portés par le service.
    } on ApiException catch (error) {
      setState(() => _inlineError = error.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyPassword() async {
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      await widget.service.requestPassword(_passwordController.text);
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
        title: Text('Se déconnecter ?', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: Text(
          'La session Telegram sera supprimée de cet appareil. '
          'Vos sources et votre catalogue restent enregistrés localement.',
          style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Annuler', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Se déconnecter', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.service.disconnect();
      if (mounted) setState(() => _stage = _Stage.intro);
    }
  }

  void _startOver() {
    setState(() {
      _stage = _Stage.phone;
      _inlineError = null;
      _codeController.clear();
      _passwordController.clear();
    });
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
            TelegramAuthState.expired => _ExpiredView(onReconnect: _startOver),
            TelegramAuthState.connecting => const _ConnectingView(),
            TelegramAuthState.codeRequired => _buildCodeForm(service),
            TelegramAuthState.passwordRequired => _buildPasswordForm(service),
            TelegramAuthState.error || TelegramAuthState.disconnected => _buildForm(service),
          },
        );
      },
    );
  }

  Widget _buildForm(TelegramService service) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      children: [
        if (_stage == _Stage.intro) ..._buildIntro(service),
        if (_stage == _Stage.phone) ..._buildPhone(service),
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

  List<Widget> _buildIntro(TelegramService service) => [
        const SizedBox(height: 18),
        const Center(child: TelegramLogo(size: 86)),
        const SizedBox(height: 22),
        Text(
          'Connectez Telegram',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        Text(
          'Connectez votre compte Telegram pour utiliser vos propres sources dans AnimeBox.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.55, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 22),
        const _InfoRow(icon: Icons.lock_outline_rounded, text: 'Votre session reste sur cet appareil, dans un stockage chiffré.'),
        const SizedBox(height: 10),
        const _InfoRow(icon: Icons.visibility_outlined, text: 'Seuls les canaux que vous ajoutez sont consultés.'),
        const SizedBox(height: 10),
        const _InfoRow(icon: Icons.phonelink_lock_rounded, text: 'Aucune donnée n\'est envoyée à un serveur externe.'),
        const SizedBox(height: 26),
        PrimaryButton(
          label: 'Connecter Telegram',
          icon: Icons.send_rounded,
          onTap: () => setState(() => _stage = _Stage.phone),
        ),
      ];

  List<Widget> _buildPhone(TelegramService service) => [
        const SizedBox(height: 8),
        Text(
          'Votre numéro de téléphone',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Un code de connexion vous sera envoyé via Telegram.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
          cursorColor: AppColors.primary,
          decoration: _fieldDecoration('+229 01 23 45 67', Icons.phone_outlined),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: _busy ? 'Connexion…' : 'Envoyer le code',
          icon: Icons.send_rounded,
          onTap: _busy ? null : _sendCode,
        ),
      ];

  Widget _buildCodeForm(TelegramService service) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      children: [
        const SizedBox(height: 8),
        Text(
          'Code Telegram',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Saisissez le code reçu dans Telegram.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 5,
          obscureText: true,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18, letterSpacing: 6),
          cursorColor: AppColors.primary,
          decoration: _fieldDecoration('• • • • •', Icons.pin_outlined).copyWith(counterText: ''),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: _busy ? 'Vérification…' : 'Continuer',
          icon: Icons.verified_outlined,
          onTap: _busy ? null : _verifyCode,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _sendCode,
            child: Text('Renvoyer le code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryBright)),
          ),
        ),
        if (_inlineError != null) ...[
          const SizedBox(height: 10),
          _ErrorBox(message: _inlineError!),
        ],
      ],
    );
  }

  Widget _buildPasswordForm(TelegramService service) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      children: [
        const SizedBox(height: 8),
        Text(
          'Mot de passe Telegram',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Votre compte est protégé par une authentification à deux facteurs.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
          cursorColor: AppColors.primary,
          decoration: _fieldDecoration('••••••••', Icons.lock_outline_rounded),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: _busy ? 'Vérification…' : 'Continuer',
          icon: Icons.verified_outlined,
          onTap: _busy ? null : _verifyPassword,
        ),
        if (_inlineError != null) ...[
          const SizedBox(height: 10),
          _ErrorBox(message: _inlineError!),
        ],
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.primaryBright, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary),
        ),
      );
}

/// État « Connexion… » pendant l'échange avec Telegram.
class _ConnectingView extends StatelessWidget {
  const _ConnectingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primaryBright),
          ),
          SizedBox(height: 16),
          Text('Connexion…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
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
          child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textSecondary)),
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
          Icon(Icons.error_outline_rounded, size: 19, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textPrimary)),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text('Réessayer', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryBright)),
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
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 15, color: AppColors.success),
                  SizedBox(width: 6),
                  StatusPill('Connecté', color: AppColors.success),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _InfoRow(icon: Icons.phonelink_lock_rounded, text: 'Connexion directe entre votre appareil et Telegram — aucun serveur intermédiaire.'),
        const SizedBox(height: 10),
        const _InfoRow(icon: Icons.storage_rounded, text: 'Session chiffrée et stockée uniquement sur cet appareil.'),
        const SizedBox(height: 22),
        PrimaryButton(
          label: 'Déconnecter',
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
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: AppColors.primaryGradient),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Center(
        child: Text(user.initials, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    );
  }
}

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
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.warning.withValues(alpha: 0.12),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Icon(Icons.timer_off_outlined, size: 40, color: AppColors.warning),
            ),
            const SizedBox(height: 18),
            Text(
              'Session expirée',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Votre session Telegram a expiré ou a été révoquée.\nReconnectez-vous pour continuer.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 22),
            PrimaryButton(label: 'Se reconnecter', icon: Icons.refresh_rounded, expanded: false, onTap: onReconnect),
          ],
        ),
      ),
    );
  }
}
