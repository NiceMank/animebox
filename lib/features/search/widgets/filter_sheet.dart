import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../anime/data/models/search_filters.dart';
import '../../anime/data/models/video_quality.dart';
import '../../anime/data/repositories/anime_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';

/// Feuille de filtres de recherche (Saison, Épisode, Qualité, Langue, Genre,
/// Source).
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.repository, required this.initial});

  final AnimeRepository repository;
  final SearchFilters initial;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late int? _season = widget.initial.season;
  late VideoQuality? _quality = widget.initial.quality;
  late String? _language = widget.initial.language;
  late String? _source = widget.initial.source;
  late Set<String> _genres = {...widget.initial.genres};
  late final TextEditingController _episodeController = TextEditingController(
    text: widget.initial.episode?.toString() ?? '',
  );

  @override
  void dispose() {
    _episodeController.dispose();
    super.dispose();
  }

  void _apply() {
    final int? episode = int.tryParse(_episodeController.text.trim());
    Navigator.of(context).pop(SearchFilters(
      season: _season,
      episode: episode,
      quality: _quality,
      language: _language,
      source: _source,
      genres: _genres,
    ));
  }

  void _reset() {
    setState(() {
      _season = null;
      _quality = null;
      _language = null;
      _source = null;
      _genres = {};
      _episodeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AnimeRepository repository = widget.repository;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filtres',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _reset,
                    child: const Text(
                      'Réinitialiser',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FilterSection(
                      title: 'Saison',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final int season in repository.availableSeasons)
                            _FilterChip(
                              label: '$season',
                              selected: _season == season,
                              onTap: () => setState(() => _season = _season == season ? null : season),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _FilterSection(
                      title: 'Épisode',
                      child: SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _episodeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          cursorColor: AppColors.primary,
                          decoration: InputDecoration(
                            hintText: 'Ex : 8',
                            hintStyle: const TextStyle(color: AppColors.textMuted),
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _FilterSection(
                      title: 'Qualité',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final VideoQuality quality in VideoQuality.values)
                            _FilterChip(
                              label: quality.label,
                              selected: _quality == quality,
                              onTap: () => setState(() => _quality = _quality == quality ? null : quality),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _FilterSection(
                      title: 'Langue',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final String language in repository.availableLanguages)
                            _FilterChip(
                              label: language,
                              selected: _language == language,
                              onTap: () => setState(() => _language = _language == language ? null : language),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _FilterSection(
                      title: 'Genre',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final String genre in repository.availableGenres)
                            _FilterChip(
                              label: genre,
                              selected: _genres.contains(genre),
                              onTap: () => setState(() {
                                if (_genres.contains(genre)) {
                                  _genres.remove(genre);
                                } else {
                                  _genres.add(genre);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _FilterSection(
                      title: 'Source',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final String source in repository.availableSources)
                            _FilterChip(
                              label: source,
                              selected: _source == source,
                              onTap: () => setState(() => _source = _source == source ? null : source),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: PrimaryButton(label: 'Appliquer les filtres', onTap: _apply),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.primary.withValues(alpha: 0.6) : AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? AppColors.primaryBright : AppColors.textSecondary),
        ),
      ),
    );
  }
}
