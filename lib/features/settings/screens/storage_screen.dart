import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../media/models/download_models.dart';
import '../services/settings_dependencies.dart';
import '../services/storage_service.dart';

/// Avertissement espace faible (§15) : seuil réel — 512 Mo libres restants.
const int kLowSpaceThresholdBytes = 512 * 1024 * 1024;

/// Écran Stockage (prompt 12 §12–§15) :
/// - tailles RÉELLES (fichiers téléchargés, cache, espace libre) ;
/// - vider le cache (confirmé — ne touche rien d'autre, §13) ;
/// - gestion des téléchargements : multi-sélection + suppression confirmée (§14) ;
/// - avertissement quand l'espace libre est faible (§15).
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key, required this.dependencies});

  final SettingsDependencies dependencies;

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  StorageSnapshot? _snapshot;
  bool _loading = true;
  bool _busy = false;
  final Set<String> _selected = <String>{};

  bool get _en => widget.dependencies.appSettings.language == 'en';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<StorageService> _service() async {
    final StorageService service = await widget.dependencies.resolveStorageService();
    if (service is DeviceStorageService) {
      // Taille réelle des fichiers téléchargés présents (§12).
      final media = widget.dependencies.mediaService;
      service.setDownloadPaths(
        media == null ? const [] : media.downloadManager.tasks.map((t) => t.localPath),
      );
    }
    return service;
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final StorageService service = await _service();
    final StorageSnapshot snapshot = await service.snapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  // -----------------------------------------------------------------------

  Future<void> _confirmClearCache() async {
    final _StorageStrings s = _StorageStrings(_en);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: Text(s.clearCache, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(s.clearCacheConfirm, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.clearCache, style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final StorageService service = await _service();
    final int freed = await service.clearCache();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.cacheCleared(formatBytes(freed)))),
    );
    await _refresh();
  }

  Future<void> _confirmDeleteSelected() async {
    final _StorageStrings s = _StorageStrings(_en);
    final int count = _selected.length;
    if (count == 0) return;
    // §14 : confirmation explicite — suppression multiple, définitive.
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: Text(s.deleteDownloadsTitle(count), style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(s.deleteDownloadsMessage(count), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.delete, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final media = widget.dependencies.mediaService;
    if (media == null) return;
    setState(() => _busy = true);
    int removed = 0;
    for (final String versionId in List<String>.of(_selected)) {
      try {
        await media.deleteDownload(versionId);
        removed++;
      } catch (_) {
        // Erreur lisible : on poursuit les autres (§28).
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.downloadsRemoved(removed))),
    );
    await _refresh();
  }

  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final _StorageStrings s = _StorageStrings(_en);
    final StorageSnapshot? snap = _snapshot;
    final media = widget.dependencies.mediaService;
    // §14 : vidéos terminées + interrompues (fichiers .part occupant
    // l'espace). Les téléchargements en cours se gèrent depuis l'écran
    // Téléchargements existant.
    final List<DownloadTask> tasks = media == null
        ? const <DownloadTask>[]
        : media.downloadManager.tasks
            .where((t) =>
                t.status == DownloadStatus.completed ||
                t.status == DownloadStatus.paused ||
                t.status == DownloadStatus.failed)
            .toList();
    final int? free = snap?.freeBytes;
    final bool lowSpace = free != null && free < kLowSpaceThresholdBytes;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(s.manageStorage, style: Theme.of(context).textTheme.headlineMedium),
              ),
              if (_selected.isNotEmpty)
                IconButton(
                  tooltip: s.delete,
                  onPressed: _busy ? null : _confirmDeleteSelected,
                  icon: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
                ),
            ]),
            const SizedBox(height: 18),

            // ---- §15 : avertissement espace faible (mesure réelle). ----
            if (lowSpace)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(s.lowSpace, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.warning)),
                  ),
                ]),
              ),

            // ---- §12 : tailles réelles (jamais fictives). ----
            _SectionLabel(s.sectionStorage),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : Column(children: [
                      _StorageRow(
                        icon: Icons.download_rounded,
                        label: s.storageDownloads,
                        value: snap?.downloadsBytes == null ? s.unknown : formatBytes(snap!.downloadsBytes!),
                      ),
                      const SizedBox(height: 12),
                      _StorageRow(
                        icon: Icons.cached_rounded,
                        label: 'Cache',
                        value: snap?.cacheBytes == null ? s.unknown : formatBytes(snap!.cacheBytes!),
                      ),
                      const SizedBox(height: 12),
                      _StorageRow(
                        icon: Icons.sd_storage_rounded,
                        label: s.storageFree,
                        value: snap?.freeBytes == null ? s.unknown : formatBytes(snap!.freeBytes!),
                      ),
                    ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _confirmClearCache,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18, color: AppColors.warning),
                label: Text(s.clearCache, style: const TextStyle(color: AppColors.warning)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ---- §14 : gestion des téléchargements (multi-sélection). ----
            _SectionLabel(s.manageDownloads.toUpperCase()),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(s.noDownloads,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  _selected.isEmpty ? s.selectHint : s.selectedCount(_selected.length),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
                ),
                child: Material(type: MaterialType.transparency, child: Column(children: [
                  for (int i = 0; i < tasks.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 58, color: AppColors.divider.withValues(alpha: 0.6)),
                    _DownloadRow(
                      task: tasks[i],
                      selected: _selected.contains(tasks[i].versionId),
                      onToggle: () {
                        if (_busy) return;
                        setState(() {
                          if (!_selected.remove(tasks[i].versionId)) {
                            _selected.add(tasks[i].versionId);
                          }
                        });
                      },
                    ),
                  ],
                ])),
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _confirmDeleteSelected,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    icon: const Icon(Icons.delete_forever_rounded, size: 18),
                    label: Text(s.deleteDownloadsTitle(_selected.length)),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Strings locales (FR principal, EN prêt — sans dépendance externe).
// ===========================================================================

class _StorageStrings {
  const _StorageStrings(this.en);

  final bool en;

  String get manageStorage => en ? 'Storage' : 'Stockage';
  String get sectionStorage => en ? 'SPACE (REAL)' : 'ESPACE (RÉEL)';
  String get storageDownloads => en ? 'Downloaded videos' : 'Vidéos téléchargées';
  String get storageFree => en ? 'Available on device' : 'Disponible sur l\'appareil';
  String get unknown => en ? 'Unknown' : 'Inconnue';
  String get lowSpace => en
      ? 'Storage is almost full. Free space with the tools below.'
      : 'L\'espace de stockage est presque plein. Libérez de la place avec les outils ci-dessous.';
  String get clearCache => en ? 'Clear cache' : 'Vider le cache';
  String get clearCacheConfirm => en
      ? 'Only the application cache will be cleared. Your downloaded videos, favorites, history, sources and catalog are NOT affected.'
      : 'Seul le cache de l\'application sera vidé. Vos vidéos téléchargées, favoris, historique, sources et catalogue ne sont PAS touchés.';
  String cacheCleared(String size) => en ? 'Cache cleared — $size freed.' : 'Cache vidé — $size libérés.';
  String get manageDownloads => en ? 'Manage downloads' : 'Gérer les téléchargements';
  String get selectHint => en ? 'Tap to select several downloads.' : 'Touchez pour sélectionner plusieurs téléchargements.';
  String selectedCount(int n) => en ? '$n selected' : '$n sélectionné(s)';
  String get noDownloads => en ? 'No completed download.' : 'Aucun téléchargement terminé.';
  String deleteDownloadsTitle(int n) => en ? 'Delete $n download(s)' : 'Supprimer $n téléchargement(s)';
  String deleteDownloadsMessage(int n) => en
      ? 'The $n selected video file(s) will be permanently deleted from this device. This cannot be undone.'
      : 'Les $n fichiers vidéo sélectionnés seront définitivement supprimés de cet appareil. Action irréversible.';
  String downloadsRemoved(int n) => en ? '$n download(s) deleted.' : '$n téléchargement(s) supprimé(s).';
  String get cancel => en ? 'Cancel' : 'Annuler';
  String get delete => en ? 'Delete' : 'Supprimer';
}

// ===========================================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppColors.textMuted),
      ),
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 20, color: AppColors.primaryBright),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary))),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
    ]);
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.task, required this.selected, required this.onToggle});

  final DownloadTask task;
  final bool selected;
  final VoidCallback onToggle;

  /// Statut visible seulement s'il n'est pas « terminé » (donnée réelle).
  String _statusSuffix(DownloadTask task) => switch (task.status) {
        DownloadStatus.paused => ' · en pause',
        DownloadStatus.failed => ' · échoué',
        DownloadStatus.downloading => ' · en cours',
        DownloadStatus.queued => ' · en attente',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          selected ? Icons.check_circle_rounded : Icons.movie_rounded,
          size: 20,
          color: selected ? AppColors.primaryBright : AppColors.textSecondary,
        ),
      ),
      title: Text(task.animeTitle,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: Text(
        'S${task.seasonNumber} · E${task.episodeNumber}'
        '${task.qualityLabel != null ? ' · ${task.qualityLabel}' : ''}'
        '${_statusSuffix(task)}',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: Checkbox(
        value: selected,
        onChanged: (_) => onToggle(),
        activeColor: AppColors.primary,
        side: const BorderSide(color: AppColors.textMuted),
      ),
      onTap: onToggle,
    );
  }
}
