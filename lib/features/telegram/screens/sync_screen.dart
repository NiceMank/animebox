import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formats.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/sync_history_tile.dart';
import '../../../shared/widgets/sync_progress_card.dart';
import '../../notifications/models/notification_models.dart';
import '../data/models/api_exception.dart';
import '../data/models/sync_history_entry.dart';
import '../data/services/telegram_service.dart';

/// Écran 8 — Synchronisation : état du moteur, statistiques globales,
/// synchronisation avec progression, historique détaillé.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.service});

  final TelegramService service;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  @override
  void initState() {
    super.initState();
    // En mode backend : recharge statistiques et historique depuis l'API.
    widget.service.loadStats().catchError((Object _) {});
  }

  /// Synchronisation MANUELLE (règle 13) : le résumé affiché reprend les
  /// valeurs RÉELLES de la passe (règle 21) — jamais de « terminé » sans
  /// synchronisation réelle (règle 32).
  Future<void> _syncNow() async {
    try {
      await widget.service.syncAll();
      if (!mounted) return;
      final SyncRunSummary? summary = widget.service.lastSyncSummary;
      if (summary == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune source à synchroniser.')),
        );
      } else {
        _showSyncSummary(context, summary);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      _presentSyncError(error);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La synchronisation a échoué. Réessayez.')),
      );
    }
  }

  /// Erreurs compréhensibles (règle 25) : session expirée (règle 24),
  /// absence Internet (règle 23), autres erreurs.
  void _presentSyncError(ApiException error) {
    if (error.kind == ApiErrorKind.unauthorized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Votre session Telegram doit être reconnectée.'),
          action: SnackBarAction(
            label: 'Reconnecter Telegram',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.telegramConnect),
          ),
        ),
      );
      return;
    }
    final String message = error.displayMessage;
    final bool offline = error.kind == ApiErrorKind.network ||
        error.kind == ApiErrorKind.timeout ||
        message.toLowerCase().contains('connexion') ||
        message.toLowerCase().contains('internet');
    if (offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connexion Internet indisponible — le catalogue local reste accessible.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Résumé RÉEL d'une synchronisation manuelle (règle 21).
  void _showSyncSummary(BuildContext context, SyncRunSummary summary) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    summary.hasErrors ? Icons.sync_problem_rounded : Icons.check_circle_rounded,
                    size: 24,
                    color: summary.hasErrors ? AppColors.warning : AppColors.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      summary.cancelled ? 'Synchronisation annulée' : 'Synchronisation terminée',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailRow(label: 'Sources analysées', value: '${summary.sourcesAnalyzed}'),
              _DetailRow(label: 'Nouveaux messages', value: '${summary.newMessages}'),
              _DetailRow(label: 'Nouveaux épisodes', value: '${summary.newEpisodes}'),
              _DetailRow(label: 'Nouvelles qualités', value: '${summary.newQualities}'),
              _DetailRow(label: 'Erreurs', value: '${summary.errors}'),
              if (summary.errorMessages.isNotEmpty)
                _DetailRow(label: 'Détail', value: summary.errorMessages.first),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Fermer',
                expanded: false,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TelegramService service = widget.service;
    return ListenableBuilder(
      listenable: service,
      builder: (BuildContext context, Widget? child) {
        final bool syncing = service.isSyncing;
        final int activeSources = service.sources.where((s) => s.syncEnabled).length;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('Synchronisation', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
            children: [
              _EngineStatus(syncing: syncing, activeSources: activeSources, lastSync: service.stats.lastSync),
              const SizedBox(height: 16),
              if (service.currentProgress != null)
                SyncProgressCard(
                  progress: service.currentProgress!,
                  finished: (service.currentProgress!.fraction ?? 0) >= 1,
                  resultEpisodes: service.stats.newEpisodes,
                ),
              if (service.currentProgress != null) const SizedBox(height: 8),
              if (syncing)
                Center(
                  child: TextButton.icon(
                    onPressed: () => widget.service.cancelSync(),
                    icon: const Icon(Icons.stop_circle_outlined, size: 17, color: AppColors.warning),
                    label: const Text(
                      'Annuler la synchronisation',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.warning),
                    ),
                  ),
                ),
              if (service.currentProgress != null) const SizedBox(height: 8),
              Row(
                children: [
                  StatTile(label: 'Publications analysées', value: formatCount(service.stats.analyzedPosts)),
                  const SizedBox(width: 10),
                  StatTile(label: 'Animés détectés', value: formatCount(service.stats.detectedAnime)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  StatTile(label: 'Épisodes détectés', value: formatCount(service.stats.detectedEpisodes)),
                  const SizedBox(width: 10),
                  StatTile(label: 'Doublons regroupés', value: formatCount(service.stats.duplicatesGrouped)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  StatTile(label: 'Nouveaux épisodes', value: formatCount(service.stats.newEpisodes), icon: Icons.fiber_new_rounded, accent: true),
                  const SizedBox(width: 10),
                  StatTile(label: 'Sources actives', value: '$activeSources', icon: Icons.rss_feed_rounded),
                ],
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: syncing ? 'Synchronisation en cours…' : 'Synchroniser maintenant',
                icon: Icons.sync_rounded,
                onTap: syncing ? null : _syncNow,
              ),
              const SizedBox(height: 26),
              Text('Historique', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ..._buildHistory(context, service.history),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildHistory(BuildContext context, List<SyncHistoryEntry> history) {
    if (history.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.history_rounded,
          title: 'Aucun historique',
          message: 'Lancez une synchronisation pour voir les résultats ici.',
        ),
      ];
    }

    final List<Widget> widgets = [];
    String? currentGroup;
    for (final SyncHistoryEntry entry in history) {
      final String group = dayGroupLabel(entry.date);
      if (group != currentGroup) {
        currentGroup = group;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(group, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ));
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SyncHistoryTile(
          entry: entry,
          onTap: () => _showEntryDetail(context, entry),
        ),
      ));
    }
    return widgets;
  }

  void _showEntryDetail(BuildContext context, SyncHistoryEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    entry.success ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 24,
                    color: entry.success ? AppColors.success : AppColors.danger,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.success ? 'Synchronisation terminée' : 'Erreur de synchronisation',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailRow(label: 'Date', value: formatDateTime(entry.date)),
              _DetailRow(label: 'Publications analysées', value: formatCount(entry.analyzedPosts)),
              _DetailRow(label: 'Nouveaux épisodes', value: '${entry.newEpisodes}'),
              if (!entry.success && entry.errorMessage != null) _DetailRow(label: 'Erreur', value: entry.errorMessage!),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Fermer',
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

class _EngineStatus extends StatelessWidget {
  const _EngineStatus({required this.syncing, required this.activeSources, required this.lastSync});

  final bool syncing;
  final int activeSources;
  final DateTime? lastSync;

  @override
  Widget build(BuildContext context) {
    final Color color = syncing ? AppColors.primaryBright : (activeSources > 0 ? AppColors.success : AppColors.textMuted);
    final String label = syncing
        ? 'Synchronisation en cours...'
        : activeSources > 0
            ? 'Moteur actif'
            : 'Moteur inactif — aucune source';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: syncing ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 10)] : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 2),
                Text(
                  lastSync == null ? 'Aucune synchronisation effectuée' : 'Dernière synchronisation : ${formatRelativeTime(lastSync!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
