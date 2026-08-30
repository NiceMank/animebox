import 'episode.dart';
import 'season.dart';
import 'video_quality.dart';

/// Modèle principal d'un animé.
///
/// Les champs `posterAsset` / `backdropAsset` pointent vers des images
/// locales pour cette étape ; ils seront remplacés par des URLs renvoyées
/// par l'API backend sans changer la structure des écrans.
class Anime {
  const Anime({
    required this.id,
    required this.title,
    required this.posterAsset,
    required this.backdropAsset,
    required this.description,
    required this.genres,
    required this.year,
    required this.seasons,
    this.languages = const ['VOSTFR'],
    this.episodeDurationMin = 24,
    this.source = 'Locale',
    this.popularity = 0,
    this.followers = 0,
    this.isFollowing = false,
  });

  final String id;
  final String title;
  final String posterAsset;
  final String backdropAsset;
  final String description;
  final List<String> genres;
  final int year;
  final List<Season> seasons;

  /// Langues disponibles (ex. `VF`, `VOSTFR`).
  final List<String> languages;
  final int episodeDurationMin;

  /// Source d'origine — sera le canal Telegram à terme.
  final String source;

  /// Score de popularité local (utilisé pour le tri des sections).
  final int popularity;
  final int followers;
  final bool isFollowing;

  int get totalEpisodes => seasons.fold(0, (int sum, Season season) => sum + season.episodeCount);

  /// Dernier épisode disponible (saison la plus récente).
  Episode? get latestEpisode {
    for (final Season season in seasons.reversed) {
      if (season.episodes.isNotEmpty) return season.episodes.last;
    }
    return null;
  }

  (int, int)? get _latestRef {
    for (final Season season in seasons.reversed) {
      if (season.episodes.isNotEmpty) return (season.number, season.episodes.last.number);
    }
    return null;
  }

  /// Libellé complet : `Saison 2 · Épisode 08` ou `Épisode 1124`.
  String get latestEpisodeTag {
    final (int, int)? ref = _latestRef;
    if (ref == null) return 'Aucun épisode';
    final (int season, int episode) = ref;
    final String number = episode.toString().padLeft(2, '0');
    return seasons.length > 1 ? 'Saison $season · Épisode $number' : 'Épisode $episode';
  }

  /// Libellé court : `S2 · E08` ou `E1124`.
  String get latestEpisodeShortTag {
    final (int, int)? ref = _latestRef;
    if (ref == null) return '—';
    final (int season, int episode) = ref;
    final String number = episode.toString().padLeft(2, '0');
    return seasons.length > 1 ? 'S$season · E$number' : 'E$episode';
  }

  /// Résumé du nombre d'épisodes : `Saison 2 · 8 épisodes` ou `1124 épisodes`.
  String get episodeMeta {
    Season? latest;
    for (final Season season in seasons.reversed) {
      if (season.episodes.isNotEmpty) {
        latest = season;
        break;
      }
    }
    if (latest == null) return 'Aucun épisode';
    if (seasons.length == 1) return '$totalEpisodes épisodes';
    return 'Saison ${latest.number} · ${latest.episodeCount} épisodes';
  }

  /// Toutes les qualités disponibles sur l'animé.
  Set<VideoQuality> get availableQualities => {
        for (final Season season in seasons)
          for (final Episode episode in season.episodes) ...episode.qualities,
      };

  Anime copyWith({bool? isFollowing}) => Anime(
        id: id,
        title: title,
        posterAsset: posterAsset,
        backdropAsset: backdropAsset,
        description: description,
        genres: genres,
        year: year,
        seasons: seasons,
        languages: languages,
        episodeDurationMin: episodeDurationMin,
        source: source,
        popularity: popularity,
        followers: followers,
        isFollowing: isFollowing ?? this.isFollowing,
      );
}
