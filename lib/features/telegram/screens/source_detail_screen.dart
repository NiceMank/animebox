import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formats.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/telegram_source_card.dart';
import '../data/models/source_status.dart';
import '../data/models/telegram_source.dart';
import '../data/services/telegram_service.dart';

/// Détails d'une source : statistiques et actions (synchroniser, activer/
/// désactiver, paramètres, supprimer).
class SourceDetailScreen extends StatefulWidget {
  const SourceDetailScreen({super.key, required this.service, required this.sourceId});

  final TelegramService service;
  final String sourceId;

  @override
  State<SourceDetailScreen> createState() => _SourceDetailScreenState();
}

class _SourceDetailScreenState extends State<SourceDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final TelegramService service = widget.service;
    if (service.sourceById(widget.sourceId) == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Source introuvable', style: TextStyle(color: AppColors.textMuted))),
      );
    }

    return ListenableBuilder(
      listenable: service,
      builder: (BuildContext context, Widget? child) {
        final TelegramSource source = service.sourceById(widget.sourceId)!;
        final bool syncing = source.status == SourceStatus.syncing;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                tooltip: 'Paramètres de la source',
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Paramètres avancés : prochaine étape.')),
                ),
                icon: const Icon(Icons.settings_outlined, size: 21),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
            children: [
              TelegramSourceCard(source: source, onTap: () {}, compact: true),
              const SizedBox(height: 16),
              Row(
                children: [
                  StatTile(label: 'Publications analysées', value: formatCount(source.analyzedPosts), icon: Icons.article_outlined),
                  const SizedBox(width: 10),
                  StatTile(label: 'Animés détectés', value: formatCount(source.detectedAnime), icon: Icons.movie_outlined),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  StatTile(label: 'Épisodes détectés', value: formatCount(source.detectedEpisodes), icon: Icons.video_library_outlined),
                  const SizedBox(width: 10),
                  StatTile(label: 'Auto-sync', value: formatAutoSyncInterval(source.autoSyncInterval), icon: Icons.autorenew_rounded),
                ],
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: syncing ? 'Synchronisation en cours…' : 'Synchroniser maintenant',
                icon: Icons.sync_rounded,
                onTap: syncing
                    ? null
                    : () {
                        service.syncSource(sourceId: source.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Synchronisation lancée…')),
                        );
                      },
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: source.syncEnabled ? 'Désactiver la source' : 'Activer la source',
                icon: source.syncEnabled ? Icons.pause_rounded : Icons.play_arrow_rounded,
                outlined: true,
                onTap: () => service.setSourceEnabled(source.id, !source.syncEnabled),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: 'Supprimer la source',
                icon: Icons.delete_outline_rounded,
                outlined: true,
                onTap: () => _confirmDelete(source),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(TelegramSource source) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Supprimer la source ?', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: Text(
          '« ${source.name} » (@${source.username}) sera retirée de vos sources.',
          style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.service.removeSource(source.id);
      Navigator.of(context).maybePop();
    }
  }
}
