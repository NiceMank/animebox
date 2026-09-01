import 'package:flutter/material.dart';

import '../../anime/data/models/anime.dart';
import '../../anime/data/models/anime_alias.dart';
import '../../anime/data/repositories/catalog_repository.dart';
import '../../../core/theme/app_colors.dart';

/// Correction manuelle (administrateur) d'une fiche dont la correspondance
/// est incertaine (`METADATA_REVIEW_REQUIRED`).
///
/// Actions disponibles — toutes explicites, jamais automatiques :
/// - associer le bon candidat (changer l'animé) ;
/// - corriger le titre affiché ;
/// - ignorer la fiche (fermer la revue).
/// Le contenu Telegram n'est jamais supprimé.
class MetadataReviewSheet extends StatefulWidget {
  const MetadataReviewSheet({
    super.key,
    required this.anime,
    required this.catalog,
    required this.onAnimeChanged,
  });

  final Anime anime;
  final CatalogRepository catalog;
  final VoidCallback onAnimeChanged;

  @override
  State<MetadataReviewSheet> createState() => _MetadataReviewSheetState();
}

class _MetadataReviewSheetState extends State<MetadataReviewSheet> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final bool ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onAnimeChanged();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action impossible pour le moment.')),
      );
    }
  }

  Future<void> _editTitle() async {
    final TextEditingController controller =
        TextEditingController(text: widget.anime.title);
    final String? title = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Corriger le titre', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: 'Titre affiché',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || title == widget.anime.title) return;
    await _run(() => widget.catalog.updateDisplayTitle(widget.anime.id, title));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 20, color: AppColors.primaryBright),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Correction manuelle',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Fiche : ${widget.anime.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            const Text(
              'Candidats proposés',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Associez explicitement la bonne fiche — rien n\'est fait automatiquement.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            if (widget.anime.metadataCandidates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Aucun candidat conservé — utilisez « Actualiser les métadonnées » sur la fiche.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              )
            else
              for (final candidate in widget.anime.metadataCandidates.take(3)) ...[
                _CandidateTile(
                  candidate: candidate,
                  onApply: _busy
                      ? null
                      : () => _run(() => widget.catalog.applyMetadataCandidate(
                            widget.anime.id,
                            candidate.providerId,
                            provider: candidate.provider,
                          )),
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _editTitle,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Corriger le titre'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(() => widget.catalog.ignoreMetadataReview(widget.anime.id)),
                    icon: const Icon(Icons.block_outlined, size: 16),
                    label: const Text('Ignorer'),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 14),
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBright),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, this.onApply});

  final MetadataCandidateInfo candidate;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final double? rawScore = candidate.score;
    final String? score = rawScore == null ? null : '${(rawScore * 100).round()} %';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    '${candidate.year ?? ''}',
                    ?candidate.provider,
                    ?score,
                  ].where((String item) => item.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onApply,
            child: const Text('Associer', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
