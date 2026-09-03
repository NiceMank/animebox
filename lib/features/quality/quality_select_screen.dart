import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/episode.dart';
import '../anime/data/models/episode_quality.dart';
import '../anime/data/models/season.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../media/models/download_models.dart';
import '../media/services/download_manager.dart';
import '../media/services/media_service.dart';
import '../../shared/widgets/episode_thumbnail.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/quality_option.dart';

/// Écran 5 — Choix de la version (qualité/langue RÉELLES) et actions
/// (Lire, Télécharger, Ouvrir dans Telegram) — prompt 8.
class QualitySelectScreen extends StatefulWidget {
  const QualitySelectScreen({
    super.key,
    required this.repository,
    required this.animeId,
    required this.episodeId,
    this.mediaService,
  });

  final AnimeRepository repository;
  final String animeId;
  final String episodeId;

  /// Couche média (null en démonstration : actions Telegram réellement
  /// indisponibles, l'interface le dit honnêtement).
  final MediaService? mediaService;

  @override
  State<QualitySelectScreen> createState() => _QualitySelectScreenState();
}

class _QualitySelectScreenState extends State<QualitySelectScreen> {
  late String _selectedQualityId;

  @override
  void initState() {
    super.initState();
    // Qualité par défaut : préférence utilisateur (Auto = meilleure
    // qualité réellement disponible), sinon la première version.
    final Episode? episode = _episode;
    if (episode == null) {
      _selectedQualityId = '';
      return;
    }
    _selectedQualityId = selectPreferredQuality(
      episode,
      widget.repository.playbackSettings.preferredQuality,
    ).id;
  }

  Episode? get _episode => widget.repository.byId(widget.animeId)?.episodeById(widget.episodeId);

  void _openPlayer() {
    Navigator.of(context).pushNamed(
      AppRoutes.player,
      arguments: EpisodeRouteArgs(animeId: widget.animeId, episodeId: widget.episodeId),
    );
  }

  EpisodeQuality? get _selectedQuality {
    for (final EpisodeQuality quality in _episode?.qualities ?? const <EpisodeQuality>[]) {
      if (quality.id == _selectedQualityId) return quality;
    }
    return null;
  }

  // -------------------------------------------------------------------
  // Téléchargement réel (règles 8/19) via la couche média
  // -------------------------------------------------------------------

  Future<void> _startDownload(EpisodeQuality quality) async {
    final MediaService? media = widget.mediaService;
    final (Season, Episode)? located = widget.repository.byId(widget.animeId)?.locateEpisode(quality.id);
    final Season? season = located?.$1;
    final Episode? episode = located?.$2;
    if (media == null || season == null || episode == null) {
      _snack('Connectez-vous à Telegram pour télécharger cet épisode.');
      return;
    }
    final DownloadManagerResult result = await media.startDownload(
      anime: widget.repository.byId(widget.animeId)!,
      season: season,
      episode: episode,
      version: quality,
    );
    _snack(result.message ?? (result.ok ? 'Téléchargement lancé.' : 'Téléchargement impossible.'));
  }

  Future<void> _openTelegram() async {
    final EpisodeQuality? quality = _selectedQuality;
    final String? link = quality?.telegramMessageLink;
    if (quality == null || link == null || link.isEmpty) return;
    final Uri uri = Uri.parse(link);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      _snack("Impossible d'ouvrir Telegram.");
    }
  }


  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final Anime? anime = widget.repository.byId(widget.animeId);
    final Episode? episode = _episode;
    if (anime == null || episode == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Épisode introuvable', style: TextStyle(color: AppColors.textMuted))),
      );
    }
    final (Season, Episode)? located = anime.locateEpisode(episode.id);
    final Season? season = located?.$1;
    final List<EpisodeQuality> available = episode.availableQualities;
    final MediaService? media = widget.mediaService;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          episode.label,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Partager',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Partage disponible dans une prochaine étape.')),
            ),
            icon: const Icon(Icons.share_outlined, size: 21),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          _EpisodeSummaryCard(anime: anime, episode: episode, season: season),
          const SizedBox(height: 22),
          const _SectionLabel(title: 'Qualité disponible', subtitle: 'Les qualités appartiennent au même épisode'),
          const SizedBox(height: 10),
          for (final EpisodeQuality quality in available) ...[
            QualityOption(
              quality: quality,
              selected: quality.id == _selectedQualityId,
              onTap: () => setState(() => _selectedQualityId = quality.id),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          const _SectionLabel(title: 'Langue / Sous-titres'),
          const SizedBox(height: 10),
          _RealLanguageCard(quality: _selectedQuality),
          const SizedBox(height: 16),
          _VersionSourceCard(quality: _selectedQuality),
          if (media != null && _selectedQuality != null) ...[
            const SizedBox(height: 14),
            _DownloadStateCard(
              media: media,
              quality: _selectedQuality!,
              onStart: () => _startDownload(_selectedQuality!),
              onPlay: _openPlayer,
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Lire maintenant',
            icon: Icons.play_arrow_rounded,
            onTap: _openPlayer,
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: (_selectedQuality?.hasTelegramLink ?? false)
                ? 'Ouvrir dans Telegram'
                : 'Aucun lien Telegram disponible',
            icon: Icons.send_rounded,
            outlined: true,
            // Désactivé proprement quand aucun lien valide n'existe :
            // on n'invente JAMAIS de lien Telegram.
            onTap: (_selectedQuality?.hasTelegramLink ?? false) ? _openTelegram : null,
          ),
        ],
      ),
    );
  }
}

/// Carte langue/sous-titres RÉELLE de la version choisie (règle 7) :
/// aucune langue n'est inventée — « Langue inconnue » si absente.
class _RealLanguageCard extends StatelessWidget {
  const _RealLanguageCard({required this.quality});

  final EpisodeQuality? quality;

  @override
  Widget build(BuildContext context) {
    final String language = (quality?.language == null || quality!.language.isEmpty)
        ? 'Langue inconnue'
        : quality!.language;
    final String subtitles = quality?.subtitles ?? '';
    final bool hasSubtitles = subtitles.isNotEmpty && subtitles != 'Aucun';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.language_rounded, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              language,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
          if (hasSubtitles) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Sous-titres $subtitles',
                maxLines: 1,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primaryBright),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// État de téléchargement RÉEL de la version choisie + actions
/// (Télécharger / Pause / Reprendre / Annuler / Lire / Supprimer).
class _DownloadStateCard extends StatelessWidget {
  const _DownloadStateCard({
    required this.media,
    required this.quality,
    required this.onStart,
    required this.onPlay,
  });

  final MediaService media;
  final EpisodeQuality quality;
  final VoidCallback onStart;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: media.downloadManager,
      builder: (BuildContext context, Widget? _) {
        final DownloadTask? task = media.downloadManager.taskForVersion(quality.id);
        if (task == null) {
          return _actionCard(
            context,
            icon: Icons.download_rounded,
            label: 'Télécharger',
            subtitle: quality.size > 0 ? 'Taille : ${quality.sizeLabel}' : null,
            onTap: onStart,
          );
        }
        switch (task.status) {
          case DownloadStatus.completed:
            return _actionCard(
              context,
              icon: Icons.check_circle_rounded,
              label: 'Téléchargé',
              subtitle: 'Lecture hors connexion disponible',
              onTap: onPlay,
              actionLabel: 'Supprimer',
              onAction: () => media.deleteDownload(quality.id),
            );
          case DownloadStatus.downloading:
            return _progressCard(context, task, onPause: () => media.pauseDownload(quality.id));
          case DownloadStatus.queued:
            return _actionCard(
              context,
              icon: Icons.schedule_rounded,
              label: 'En attente',
              subtitle: 'Dans la file de téléchargement',
              actionLabel: 'Annuler',
              onAction: () => media.cancelDownload(quality.id),
            );
          case DownloadStatus.paused:
            return _actionCard(
              context,
              icon: Icons.pause_circle_rounded,
              label: 'Téléchargement interrompu',
              subtitle: _progressLabel(task),
              onTap: () => media.resumeDownload(quality.id),
              actionLabel: 'Annuler',
              onAction: () => media.cancelDownload(quality.id),
            );
          case DownloadStatus.failed:
            return _actionCard(
              context,
              icon: Icons.error_outline_rounded,
              label: 'Échec du téléchargement',
              subtitle: task.error ?? 'Réessayez.',
              onTap: task.resumable ? () => media.resumeDownload(quality.id) : onStart,
              actionLabel: 'Annuler',
              onAction: () => media.cancelDownload(quality.id),
            );
          case DownloadStatus.cancelled:
            return _actionCard(
              context,
              icon: Icons.download_rounded,
              label: 'Télécharger',
              subtitle: 'Téléchargement annulé',
              onTap: onStart,
            );
        }
      },
    );
  }

  String _progressLabel(DownloadTask task) {
    final double? fraction = task.fraction;
    if (fraction != null) return '${(fraction * 100).round()} %';
    return 'Reprise possible';
  }

  Widget _progressCard(BuildContext context, DownloadTask task, {required VoidCallback onPause}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.downloading_rounded, size: 18, color: AppColors.primaryBright),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.fraction == null ? 'Téléchargement en cours' : '${(task.fraction! * 100).round()} %',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              IconButton(
                tooltip: 'Pause',
                onPressed: onPause,
                icon: Icon(Icons.pause_rounded, size: 19, color: AppColors.textSecondary),
              ),
              IconButton(
                tooltip: 'Annuler',
                onPressed: () => media.cancelDownload(quality.id),
                icon: Icon(Icons.close_rounded, size: 19, color: AppColors.textSecondary),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: task.fraction,
              minHeight: 5,
              backgroundColor: AppColors.surfaceAlt,
              color: AppColors.primaryBright,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.primaryBright),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  if (subtitle != null)
                    Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _VersionSourceCard extends StatelessWidget {
  const _VersionSourceCard({required this.quality});

  final EpisodeQuality? quality;

  @override
  Widget build(BuildContext context) {
    final String channel = quality?.sourceChannelUsername ?? '—';
    final int? messageId = quality?.telegramMessageId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.send_outlined, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Publication d\'origine',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  messageId == null ? 'Canal : $channel' : 'Canal : $channel · message #$messageId',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: Theme.of(context).textTheme.labelSmall),
        ],
      ],
    );
  }
}

/// Carte résumant l'épisode choisi (miniature, animé, saison, titre).
class _EpisodeSummaryCard extends StatelessWidget {
  const _EpisodeSummaryCard({required this.anime, required this.episode, required this.season});

  final Anime anime;
  final Episode episode;
  final Season? season;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          EpisodeThumbnail(asset: episode.thumbnail, width: 120, height: 72, borderRadius: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anime.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  season == null ? episode.label : 'Saison ${season!.number} · Épisode ${episode.number.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryBright),
                ),
                const SizedBox(height: 3),
                Text(
                  episode.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
