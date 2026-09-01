import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formats.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/models/api_exception.dart';
import '../data/models/resolved_channel.dart';
import '../data/models/telegram_input.dart';
import '../data/services/telegram_service.dart';

/// Écran d'ajout d'une source Telegram.
///
/// La saisie est validée localement, puis la résolution réelle (canal
/// introuvable, inaccessible, accessible) est déléguée au backend via
/// [TelegramService.resolveChannel]. Un aperçu est affiché avant l'ajout.
class SourceAddScreen extends StatefulWidget {
  const SourceAddScreen({super.key, required this.service});

  final TelegramService service;

  @override
  State<SourceAddScreen> createState() => _SourceAddScreenState();
}

class _SourceAddScreenState extends State<SourceAddScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _checking = false;
  bool _adding = false;
  ResolvedChannel? _preview;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isInviteLink {
    final String text = _controller.text.trim();
    return text.contains('t.me/+') || text.contains('t.me/joinchat');
  }

  Future<void> _previewSource() async {
    // 1. Validation locale (message immédiat, sans réseau).
    // Les liens d'invitation (t.me/+hash) ne passent pas par le parseur
    // d'usernames : ils sont résolus tels quels par le service.
    final String input;
    if (_isInviteLink) {
      input = _controller.text.trim();
    } else {
      try {
        input = TelegramInputParser.parse(_controller.text);
      } on ApiException catch (error) {
        setState(() {
          _error = error.displayMessage;
          _preview = null;
        });
        return;
      }
    }

    // 2. Résolution réelle : le compte connecté vérifie l'accessibilité.
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final ResolvedChannel channel = await widget.service.resolveChannel(input);
      if (!mounted) return;
      setState(() => _preview = channel);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _error = error.displayMessage;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _addSource() async {
    final ResolvedChannel? preview = _preview;
    if (preview == null) return;
    setState(() => _adding = true);
    try {
      await widget.service.addSource(
        name: preview.title,
        username: preview.username,
        channelId: preview.channelId?.toString(),
        kind: switch (preview.kind) {
          ChannelKind.group => 'group',
          ChannelKind.private => 'private',
          ChannelKind.channel => 'channel',
        },
        inviteHash: preview.inviteHash,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Source « ${preview.title} » ajoutée.')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _adding = false;
        _error = error.displayMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Ajouter une source', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          Text(
            'Saisissez le nom d\'utilisateur ou le lien Telegram du canal.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _previewSource(),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
            cursorColor: AppColors.primary,
            decoration: InputDecoration(
              hintText: '@animechannel ou https://t.me/animechannel',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
              prefixIcon: const Icon(Icons.alternate_email_rounded, color: AppColors.primaryBright, size: 20),
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
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: _checking ? 'Vérification…' : 'Vérifier',
            icon: Icons.search_rounded,
            onTap: _checking ? null : _previewSource,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
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
                    child: Text(_error!, style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
          ],
          if (_preview != null) ...[
            const SizedBox(height: 24),
            Text('Aperçu de la source', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _PreviewCard(channel: _preview!, onAdd: _adding ? null : _addSource, adding: _adding),
            const SizedBox(height: 8),
            const Text(
              'La source sera synchronisée depuis votre compte Telegram connecté.',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Aperçu du canal résolu par le backend (photo, titre, @username,
/// description) avec le bouton d'ajout.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.channel, required this.onAdd, required this.adding});

  final ResolvedChannel channel;
  final VoidCallback? onAdd;
  final bool adding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ChannelAvatar(channel: channel),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      channel.username.isEmpty
                          ? 'Lien d\'invitation privé'
                          : '@${channel.username}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (channel.memberCount != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${formatCount(channel.memberCount!)} abonnés',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryBright),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                ),
                child: Text(
                  channel.kind.label,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.success),
                ),
              ),
            ],
          ),
          if (channel.description != null && channel.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              channel.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: adding ? 'Ajout en cours…' : 'Ajouter cette source',
            icon: Icons.add_rounded,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _ChannelAvatar extends StatelessWidget {
  const _ChannelAvatar({required this.channel});

  final ResolvedChannel channel;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: AppColors.primaryGradient),
      ),
      padding: const EdgeInsets.all(11),
      child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 22),
    );
    final String? photo = channel.photoUrl;
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipOval(
        child: photo == null || photo.isEmpty
            ? fallback
            : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}
