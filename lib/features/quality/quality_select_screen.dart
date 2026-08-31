import 'package:flutter/material.dart';

import '../anime/data/models/anime.dart';
import '../anime/data/models/episode.dart';
import '../anime/data/models/episode_quality.dart';
import '../anime/data/models/season.dart';
import '../anime/data/repositories/anime_repository.dart';
import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/episode_thumbnail.dart';
import '../../shared/widgets/language_option.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/quality_option.dart';
import '../../shared/widgets/telegram_placeholder_sheet.dart';

/// Écran 5 — Choix de la qualité, de la langue et des actions
/// (Lire maintenant, Télécharger, Ouvrir dans Telegram).
class QualitySelectScreen extends StatefulWidget {
  const QualitySelectScreen({
    super.key,
    required this.repository,
    required this.animeId,
    required this.episodeId,
  });

  final AnimeRepository repository;
  final String animeId;
  final String episodeId;

  @override
  State<QualitySelectScreen> createState() => _QualitySelectScreenState();
}

class _QualitySelectScreenState extends State<QualitySelectScreen> {
  late String _selectedQualityId;
  late String _selectedLanguage;

  /// Options de langue simulées (mock).
  static const List<(String, String?)> _languageOptions = [
    ('VF', 'Français'),
    ('VO', 'Japonais'),
    ('VOSTFR', 'Sous-titré FR'),
  ];

  @override
  void initState() {
    super.initState();
    final Episode? episode = _episode;
    final List<EpisodeQuality> available = episode?.availableQualities ?? const [];
    _selectedQualityId = available.isEmpty ? '' : available.first.id;
    _selectedLanguage = _languageOptions.first.$1;
  }

  Episode? get _episode => widget.repository.byId(widget.animeId)?.episodeById(widget.episodeId);

  void _openPlayer() {
    Navigator.of(context).pushNamed(
      AppRoutes.player,
      arguments: EpisodeRouteArgs(animeId: widget.animeId, episodeId: widget.episodeId),
    );
  }

  void _mockDownload() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Téléchargement en préparation… (${_selectedQuality?.sizeLabel ?? ''})')),
    );
  }

  EpisodeQuality? get _selectedQuality {
    for (final EpisodeQuality quality in _episode?.qualities ?? const <EpisodeQuality>[]) {
      if (quality.id == _selectedQualityId) return quality;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Anime? anime = widget.repository.byId(widget.animeId);
    final Episode? episode = _episode;
    if (anime == null || episode == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Épisode introuvable', style: TextStyle(color: AppColors.textMuted))),
      );
    }
    final (Season, Episode)? located = anime.locateEpisode(episode.id);
    final Season? season = located?.$1;
    final List<EpisodeQuality> available = episode.availableQualities;

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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (String label, String? subtitle) in _languageOptions)
                LanguageOption(
                  label: label,
                  subtitle: subtitle,
                  selected: _selectedLanguage == label,
                  onTap: () => setState(() => _selectedLanguage = label),
                ),
            ],
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Lire maintenant',
            icon: Icons.play_arrow_rounded,
            onTap: _openPlayer,
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Télécharger',
            icon: Icons.download_rounded,
            outlined: true,
            onTap: _mockDownload,
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Ouvrir dans Telegram',
            icon: Icons.send_rounded,
            outlined: true,
            onTap: () => TelegramPlaceholderSheet.show(context),
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
        Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryBright),
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
