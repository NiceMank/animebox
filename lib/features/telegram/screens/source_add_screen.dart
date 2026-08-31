import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/models/source_status.dart';
import '../data/models/telegram_source.dart';
import '../data/services/telegram_service.dart';
import 'widgets/source_preview_card.dart';

/// Écran d'ajout d'une source Telegram (validation locale uniquement).
class SourceAddScreen extends StatefulWidget {
  const SourceAddScreen({super.key, required this.service});

  final TelegramService service;

  @override
  State<SourceAddScreen> createState() => _SourceAddScreenState();
}

class _SourceAddScreenState extends State<SourceAddScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  String _username = '';
  String _name = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Valide la saisie : @username, https://t.me/xxx ou xxx acceptés.
  /// Retourne null si valide, sinon le message d'erreur.
  String? _validate(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) return 'Veuillez saisir une source.';

    String candidate = trimmed;
    if (candidate.startsWith('@')) candidate = candidate.substring(1);
    final Uri? uri = Uri.tryParse(candidate);
    if (uri != null && uri.host.isNotEmpty && candidate.startsWith('http')) {
      // Liens : https://t.me/animechannel
      if (uri.host != 't.me') return 'Format de source invalide.';
      candidate = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    } else if (candidate.contains('/')) {
      return 'Format de source invalide.';
    }

    // Username Telegram : lettres, chiffres et underscores (3 à 32).
    final RegExp valid = RegExp(r'^[A-Za-z][A-Za-z0-9_]{2,31}$');
    if (!valid.hasMatch(candidate)) return 'Format de source invalide.';
    return null;
  }

  void _onChanged(String value) {
    setState(() {
      _error = null;
      _username = '';
    });
  }

  void _preview() {
    final String trimmed = _controller.text.trim();
    final String? error = _validate(trimmed);
    if (error != null) {
      setState(() {
        _error = error;
        _username = '';
      });
      return;
    }
    String username = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    final Uri? uri = Uri.tryParse(username);
    if (uri != null && uri.host.isNotEmpty && username.startsWith('http')) {
      username = uri.pathSegments.first;
    }
    setState(() {
      _error = null;
      _username = username;
      _name = username.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    });
  }

  void _add() {
    if (_username.isEmpty) {
      _preview();
      return;
    }
    final TelegramSource source = widget.service.addSource(name: _name, username: _username);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Source « ${source.name} » ajoutée.')),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final bool showPreview = _username.isNotEmpty;

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
            onChanged: _onChanged,
            onSubmitted: (_) => _preview(),
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
              errorText: _error,
              errorStyle: const TextStyle(fontSize: 11.5, color: AppColors.danger),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Vérifier', icon: Icons.search_rounded, onTap: _preview),
          if (showPreview) ...[
            const SizedBox(height: 24),
            Text('Aperçu de la source', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            SourcePreviewCard(
              source: TelegramSource(
                id: 'preview',
                name: _name,
                username: _username,
                status: widget.service.simulatedSourceStatus ?? SourceStatus.active,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'La vérification réelle du canal sera effectuée lors de la connexion à l\'API Telegram (prochaine étape).',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Ajouter la source', icon: Icons.add_rounded, onTap: _add),
          ],
        ],
      ),
    );
  }
}
