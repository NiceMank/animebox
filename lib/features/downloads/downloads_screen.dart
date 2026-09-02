import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../media/models/download_models.dart';
import '../media/services/download_manager.dart';
import '../media/services/media_service.dart';
import '../../shared/widgets/empty_state.dart';

/// Écran Téléchargements (prompt 8, règle 18) : EN COURS · EN ATTENTE ·
/// TERMINÉS · ERREURS, avec les actions réelles sur chaque téléchargement.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.onBrowse, this.mediaService});

  final VoidCallback onBrowse;

  /// Couche média (null en démonstration : écran vide honnête).
  final MediaService? mediaService;

  @override
  Widget build(BuildContext context) {
    final DownloadManager? manager = mediaService?.downloadManager;
    if (manager == null) {
      return SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _Header(),
            ),
            Expanded(
              child: EmptyState(
                icon: Icons.download_rounded,
                title: 'Aucun téléchargement',
                message: 'Connectez Telegram puis téléchargez vos épisodes : ils apparaîtront ici.',
                actionLabel: 'Parcourir la bibliothèque',
                onAction: onBrowse,
              ),
            ),
          ],
        ),
      );
    }
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: manager,
        builder: (BuildContext context, Widget? _) {
          final List<DownloadTask> tasks = manager.tasks;
          final List<DownloadTask> active = tasks
              .where((DownloadTask t) => t.status == DownloadStatus.downloading)
              .toList();
          final List<DownloadTask> queued = tasks
              .where((DownloadTask t) => t.status == DownloadStatus.queued)
              .toList();
          final List<DownloadTask> paused = tasks
              .where((DownloadTask t) => t.status == DownloadStatus.paused)
              .toList();
          final List<DownloadTask> completed = tasks
              .where((DownloadTask t) => t.status == DownloadStatus.completed)
              .toList();
          final List<DownloadTask> errored = tasks
              .where((DownloadTask t) =>
                  t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled)
              .toList();

          final bool nothing = active.isEmpty &&
              queued.isEmpty &&
              paused.isEmpty &&
              completed.isEmpty &&
              errored.isEmpty;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _Header(),
              ),
              Expanded(
                child: nothing
                    ? EmptyState(
                        icon: Icons.download_rounded,
                        title: 'Aucun téléchargement',
                        message:
                            'Les épisodes téléchargés depuis vos sources Telegram apparaîtront ici.',
                        actionLabel: 'Parcourir la bibliothèque',
                        onAction: onBrowse,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                        children: [
                          if (active.isNotEmpty) ...<Widget>[
                            const _SectionTitle('EN COURS'),
                            for (final DownloadTask task in active) ...<Widget>[
                              const SizedBox(height: 8),
                              _TaskCard(task: task, media: mediaService!),
                            ],
                          ],
                          if (queued.isNotEmpty) ...<Widget>[
                            const _SectionTitle('EN ATTENTE'),
                            for (final DownloadTask task in queued) ...<Widget>[
                              const SizedBox(height: 8),
                              _TaskCard(task: task, media: mediaService!),
                            ],
                          ],
                          if (paused.isNotEmpty) ...<Widget>[
                            const _SectionTitle('INTERROMPUS'),
                            for (final DownloadTask task in paused) ...<Widget>[
                              const SizedBox(height: 8),
                              _TaskCard(task: task, media: mediaService!),
                            ],
                          ],
                          if (completed.isNotEmpty) ...<Widget>[
                            const _SectionTitle('TERMINÉS'),
                            for (final DownloadTask task in completed) ...<Widget>[
                              const SizedBox(height: 8),
                              _TaskCard(task: task, media: mediaService!),
                            ],
                          ],
                          if (errored.isNotEmpty) ...<Widget>[
                            const _SectionTitle('ERREURS'),
                            for (final DownloadTask task in errored) ...<Widget>[
                              const SizedBox(height: 8),
                              _TaskCard(task: task, media: mediaService!),
                            ],
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Text('Téléchargements', style: Theme.of(context).textTheme.headlineMedium);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Carte d'un téléchargement : identité réelle (anime, S0xE0y, qualité,
/// langue), progression réelle, actions adaptées à l'état (règle 19).
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.media});

  final DownloadTask task;
  final MediaService media;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: task.status == DownloadStatus.downloading
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: task.status == DownloadStatus.completed
                      ? const LinearGradient(colors: AppColors.primaryGradient)
                      : null,
                  color: task.status == DownloadStatus.completed ? null : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  task.status == DownloadStatus.completed
                      ? Icons.play_arrow_rounded
                      : Icons.movie_outlined,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.animeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _identityLabel(),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primaryBright),
                    ),
                  ],
                ),
              ),
              ..._actions(context),
            ],
          ),
          if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.paused) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: task.fraction,
                minHeight: 5,
                backgroundColor: AppColors.surfaceAlt,
                color: AppColors.primaryBright,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _progressLabel(),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
          if (task.error != null && task.error!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              task.error!,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  String _identityLabel() {
    final String code = 'S${task.seasonNumber.toString().padLeft(2, '0')}'
        'E${task.episodeNumber.toString().padLeft(2, '0')}';
    final String quality = task.qualityLabel ?? '—';
    final String language = task.language ?? '';
    return '$code · $quality${language.isEmpty ? '' : ' · $language'}';
  }

  String _progressLabel() {
    final double? fraction = task.fraction;
    final List<String> parts = <String>[];
    if (fraction != null) {
      parts.add('${(fraction * 100).round()} %');
    }
    if (task.expectedSize != null) {
      parts.add('${_gigaMo(task.downloadedBytes)} / ${_gigaMo(task.expectedSize!)}');
    } else if (task.downloadedBytes > 0) {
      parts.add('${_gigaMo(task.downloadedBytes)} reçus');
    }
    if (task.speedBytesPerSec != null && task.speedBytesPerSec! > 0) {
      parts.add(_moSec(task.speedBytesPerSec!));
    }
    if (task.eta != null && task.eta!.inSeconds > 0) {
      parts.add('reste ${_duree(task.eta!)}');
    }
    return parts.join(' · ');
  }

  String _gigaMo(int bytes) {
    final double go = bytes / (1024 * 1024 * 1024);
    if (go >= 1) return '${go.toStringAsFixed(go >= 10 ? 0 : 1)} Go';
    return '${(bytes / (1024 * 1024)).round()} Mo';
  }

  String _moSec(double bytesPerSec) {
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} Mo/s';
  }

  String _duree(Duration eta) {
    if (eta.inMinutes >= 1) return '${eta.inMinutes} min';
    return '${eta.inSeconds} s';
  }

  List<Widget> _actions(BuildContext context) {
    switch (task.status) {
      case DownloadStatus.downloading:
        return <Widget>[
          _icon(Icons.pause_rounded, 'Pause', () => media.pauseDownload(task.versionId)),
          _icon(Icons.close_rounded, 'Annuler', () => _confirmCancel(context)),
        ];
      case DownloadStatus.queued:
        return <Widget>[
          _icon(Icons.close_rounded, 'Annuler', () => _confirmCancel(context)),
        ];
      case DownloadStatus.paused:
        return <Widget>[
          _icon(Icons.play_arrow_rounded, 'Reprendre', () => media.resumeDownload(task.versionId)),
          _icon(Icons.close_rounded, 'Annuler', () => _confirmCancel(context)),
        ];
      case DownloadStatus.completed:
        return <Widget>[
          _icon(Icons.delete_outline_rounded, 'Supprimer', () => media.deleteDownload(task.versionId)),
        ];
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return <Widget>[
          if (task.resumable)
            _icon(Icons.refresh_rounded, 'Reprendre', () => media.resumeDownload(task.versionId)),
          _icon(Icons.delete_outline_rounded, 'Supprimer', () => media.deleteDownload(task.versionId)),
        ];
    }
  }


  /// Annulation — confirmation avant suppression du fichier temporaire
  /// (règle 12). Le catalogue n'est jamais touché (règle 20).
  Future<void> _confirmCancel(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Annuler ce téléchargement ?', style: TextStyle(fontSize: 16)),
        content: const Text(
          'Le fichier partiel sera supprimé. L\'épisode reste disponible dans le catalogue.',
          style: TextStyle(fontSize: 13),
        ),
        actions: <TextButton>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Annuler le téléchargement'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await media.cancelDownload(task.versionId);
    }
  }

  Widget _icon(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: AppColors.textSecondary),
    );
  }
}
