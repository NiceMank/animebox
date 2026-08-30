import 'video_quality.dart';

/// Filtres de recherche — tous les champs sont optionnels.
class SearchFilters {
  const SearchFilters({
    this.season,
    this.episode,
    this.quality,
    this.language,
    this.genres = const {},
    this.source,
  });

  static const SearchFilters empty = SearchFilters();

  final int? season;
  final int? episode;
  final VideoQuality? quality;
  final String? language;
  final Set<String> genres;
  final String? source;

  bool get isActive =>
      season != null ||
      episode != null ||
      quality != null ||
      language != null ||
      genres.isNotEmpty ||
      source != null;

  /// Nombre de groupes de filtres actifs (affiché sur le bouton de filtres).
  int get activeCount =>
      (season != null ? 1 : 0) +
      (episode != null ? 1 : 0) +
      (quality != null ? 1 : 0) +
      (language != null ? 1 : 0) +
      (genres.isNotEmpty ? 1 : 0) +
      (source != null ? 1 : 0);

  /// Copie avec remplacement ; passer `null` efface le champ correspondant.
  SearchFilters copyWith({
    Object? season = _unset,
    Object? episode = _unset,
    Object? quality = _unset,
    Object? language = _unset,
    Object? genres = _unset,
    Object? source = _unset,
  }) {
    return SearchFilters(
      season: identical(season, _unset) ? this.season : season as int?,
      episode: identical(episode, _unset) ? this.episode : episode as int?,
      quality: identical(quality, _unset) ? this.quality : quality as VideoQuality?,
      language: identical(language, _unset) ? this.language : language as String?,
      genres: identical(genres, _unset) ? this.genres : Set<String>.from(genres as Set<String>),
      source: identical(source, _unset) ? this.source : source as String?,
    );
  }

  static const Object _unset = Object();
}
