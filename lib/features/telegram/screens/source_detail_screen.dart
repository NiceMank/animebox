import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formats.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/telegram_source_card.dart';
import '../data/models/source_status.dart';
import '../data/models/telegram_source.dart';
import '../data/services/telegram_service.dart';
import '../../../app/router.dart';

/// Détails d'une source : statistiques, synchronisation, interruption
/// auto-sync, publications récentes et suppression (avec confirmation).
class SourceDetailScreen extends StatefulWidget {
  const SourceDetailScreen({super.key, required this.service, required this.sourceId});

  final TelegramService service;
  final String sourceId;

  @override
  State<SourceDetailScreen> createState() => _SourceDetailScreenState();
}

class _SourceDetailScreenState extends State<SourceDetailScreen> {
  bool _syncing = false;

  Future<void> _syncNow(TelegramSource source) async {
    setState(() => _syncing = true);
    try {
      await widget.service.syncSource(sourceId: source.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Synchronisation terminée.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La synchronisation a échoué. Réessayez.')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

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
        // Re-testé à chaque notification : la source peut disparaître
        // (suppression) pendant que l'écran est encore affiché.
        final TelegramSource? source = service.sourceById(widget.sourceId);
        if (source == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Source introuvable', style: TextStyle(color: AppColors.textMuted))),
          );
        }
        final bool syncing = source.status == SourceStatus.syncing || _syncing;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
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
              const SizedBox(height: 16),
              // Synchronisation automatique : modifie l'état enregistré
              // (la vraie exécution périodique viendra dans une prochaine étape).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.autorenew_rounded, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Synchronisation automatique', style: Theme.of(context).textTheme.titleSmall),
                          Text(
                            source.syncEnabled ? 'Activée' : 'Désactivée',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: source.syncEnabled,
                      activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                      activeThumbColor: AppColors.primaryBright,
                      onChanged: (bool enabled) =>
                          widget.service.setSourceEnabled(source.id, enabled),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: syncing ? 'Synchronisation en cours…' : 'Synchroniser maintenant',
                icon: Icons.sync_rounded,
                onTap: syncing ? null : () => _syncNow(source),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: 'Publications récentes',
                icon: Icons.article_outlined,
                outlined: true,
                onTap: () => Navigator.of(context).pushNamed(
                  AppRoutes.sourcePublications,
                  arguments: source.id,
                ),
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
        title: const Text('Supprimer cette source ?', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: const Text(
          'Les données associées à cette source pourront également être supprimées selon les règles de conservation définies par l\'application.',
          style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
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
      await widget.service.removeSource(source.id);
      if (mounted) Navigator.of(context).maybePop();
    }
  }
}
