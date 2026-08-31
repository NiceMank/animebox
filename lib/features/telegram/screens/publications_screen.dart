import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formats.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../anime/data/models/episode_quality.dart' show formatBytes;
import '../data/models/api_exception.dart';
import '../data/models/telegram_message.dart';
import '../data/services/telegram_service.dart';

/// Écran temporaire de vérification : dernières publications récupérées
/// d'une source (debug de l'intégration Telegram).
///
/// Chaque publication affiche son ID, sa date, son texte, son type de
/// média et un bouton « Ouvrir dans Telegram » actif uniquement lorsqu'un
/// lien valide existe (jamais de lien inventé).
class PublicationsScreen extends StatefulWidget {
  const PublicationsScreen({super.key, required this.service, required this.sourceId});

  final TelegramService service;
  final String sourceId;

  @override
  State<PublicationsScreen> createState() => _PublicationsScreenState();
}

class _PublicationsScreenState extends State<PublicationsScreen> {
  bool _loading = true;
  String? _error;
  List<TelegramMessage> _messages = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<TelegramMessage> messages =
          await widget.service.fetchMessages(widget.sourceId, limit: 20);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.displayMessage;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? sourceName = widget.service.sourceById(widget.sourceId)?.name;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Publications récentes', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
      ),
      body: _buildBody(sourceName),
    );
  }

  Widget _buildBody(String? sourceName) {
    if (_loading) {
      return SkeletonPulse(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          itemCount: 6,
          itemBuilder: (_, _) => const PublicationSkeleton(),
          separatorBuilder: (_, _) => const SizedBox(height: 10),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              PrimaryButton(label: 'Réessayer', icon: Icons.refresh_rounded, expanded: false, onTap: _load),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text('Aucune publication accessible.', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        itemCount: _messages.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                sourceName == null
                    ? '${_messages.length} publications récupérées'
                    : '$sourceName · ${_messages.length} publications récupérées',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
              ),
            );
          }
          return _PublicationTile(message: _messages[index - 1]);
        },
        separatorBuilder: (_, _) => const SizedBox(height: 10),
      ),
    );
  }
}

class _PublicationTile extends StatelessWidget {
  const _PublicationTile({required this.message});

  final TelegramMessage message;

  IconData get _mediaIcon => switch (message.mediaType) {
        TelegramMediaType.video => Icons.videocam_rounded,
        TelegramMediaType.image => Icons.image_rounded,
        TelegramMediaType.document => Icons.insert_drive_file_rounded,
        TelegramMediaType.text => Icons.notes_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final bool hasLink = message.messageLink != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_mediaIcon, size: 19, color: AppColors.primaryBright),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message #${message.messageId}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryBright),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatRelativeTime(message.date),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: hasLink ? 'Ouvrir dans Telegram' : 'Aucun lien Telegram disponible',
                onPressed: hasLink ? () => _showLink(context, message.messageLink!) : null,
                icon: Icon(Icons.open_in_new_rounded, size: 19, color: hasLink ? AppColors.primaryBright : AppColors.textMuted),
              ),
            ],
          ),
          if (message.text != null && message.text!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message.text!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textPrimary),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Text(
                  message.mediaType.label,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (message.fileName != null) message.fileName!,
                    if (message.fileSize != null) formatBytes(message.fileSize!),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLink(BuildContext context, String link) {
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
              const Text(
                'Lien Telegram',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: SelectableText(link, style: const TextStyle(fontSize: 13, color: AppColors.primaryBright)),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Copier le lien',
                icon: Icons.copy_rounded,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lien copié.')),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              PrimaryButton(
                label: 'Fermer',
                outlined: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
