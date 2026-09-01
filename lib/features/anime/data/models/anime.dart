import 'anime_alias.dart';
import 'episode.dart';
import 'metadata_status.dart';
import 'season.dart';
import 'video_quality.dart';

/// Statut de diffusion d'un animé.
enum AnimeStatus { ongoing, completed, upcoming }

extension AnimeStatusX on AnimeStatus {
  String get label => switch (this) {
        AnimeStatus.ongoing => 'En cours',
        AnimeStatus.completed => 'Terminé',
        AnimeStatus.upcoming => 'À venir',
      };
}

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
    this.rating = 0,
    this.status = AnimeStatus.ongoing,
    this.languages = const ['VOSTFR'],
    this.episodeDurationMin = 24,
    this.source = 'Locale',
    this.popularity = 0,
    this.followers = 0,
    this.isFollowing = false,
    this.canonicalTitle,
    this.originalTitle,
    this.alternativeTitles = const [],
    this.aliases = const [],
    this.metadataStatus = MetadataStatus.pending,
    this.metadataSource,
    this.metadataUpdatedAt,
    this.metadataCandidates = const [],
    this.totalEpisodesDeclared,
    this.seasonCountDeclared,
    this.episodeDurationMinDeclared,
    this.posterUrl,
    this.backdropUrl,
  });

  final String id;
  final String title;
  final String posterAsset;
  final String backdropAsset;
  final String description;
  final List<String> genres;
  final int year;
  final List<Season> seasons;

  /// Note moyenne (0 à 10).
  final double rating;
  final AnimeStatus status;

  /// Langues disponibles (ex. `VF`, `VOSTFR`).
  final List<String> languages;
  final int episodeDurationMin;

  /// Source d'origine — sera le canal Telegram à terme.
  final String source;

  /// Score de popularité local (utilisé pour le tri des sections).
  final int popularity;
  final int followers;
  final bool isFollowing;

  // ---- Métadonnées du catalogue (étape 6) ----

  /// Titre canonique (identité de la fiche, ex. « Solo Leveling »).
  final String? canonicalTitle;

  /// Titre original (ex. « Ore dake Level Up na Ken »).
  final String? originalTitle;

  /// Autres titres connus (jamais inventés).
  final List<String> alternativeTitles;

  /// Alias utilisés par la correspondance backend.
  final List<AnimeAlias> aliases;

  /// État d'enrichissement des métadonnées.
  final MetadataStatus metadataStatus;

  /// Fournisseur de métadonnées (« local », « jikan »…).
  final String? metadataSource;

  /// Date de dernière mise à jour des métadonnées (ISO 8601).
  final String? metadataUpdatedAt;

  /// Candidats proposés quand la correspondance est incertaine (revue).
  final List<MetadataCandidateInfo> metadataCandidates;

  /// Nombre total d'épisodes annoncé par le fournisseur (ex. 24).
  /// Distinct des épisodes réellement disponibles sur Telegram.
  final int? totalEpisodesDeclared;

  /// Nombre de saisons annoncé par le fournisseur.
  final int? seasonCountDeclared;

  /// Durée d'épisode annoncée par le fournisseur (minutes).
  final int? episodeDurationMinDeclared;

  /// URL d'affiche verticale (cache d'images backend).
  final String? posterUrl;

  /// URL de fond horizontal (cache d'images backend).
  final String? backdropUrl;

  /// La fiche attend-elle encore des informations complètes ?
  bool get isMetadataPending => metadataStatus.isPendingInfo;

  /// Une décision humaine est-elle attendue (correspondance incertaine) ?
  bool get needsMetadataReview => metadataStatus.needsReview;

  /// Total d'épisodes annoncé par le fournisseur, sinon le nombre connu.
  int get totalEpisodesAnnounced => totalEpisodesDeclared ?? totalEpisodes;

  /// Tous les titres connus de la fiche (pour la recherche locale).
  List<String> get allTitles => [
        title,
        ?canonicalTitle,
        ?originalTitle,
        ...alternativeTitles,
        for (final AnimeAlias alias in aliases) alias.value,
      ];

  int get totalEpisodes => seasons.fold(0, (int sum, Season season) => sum + season.episodeCount);

  bool get hasSpecials => seasons.any((Season season) => season.specials.isNotEmpty);

  /// Tous les épisodes de l'animé, saison par saison.
  List<Episode> get allEpisodes => [
        for (final Season season in seasons) ...[...season.episodes, ...season.specials],
      ];

  Episode? episodeById(String episodeId) {
    for (final Season season in seasons) {
      final Episode? found = season.episodeById(episodeId);
      if (found != null) return found;
    }
    return null;
  }

  /// Dernier épisode disponible (saison la plus récente).
  Episode? get latestEpisode {
    for (final Season season in seasons.reversed) {
      if (season.episodes.isNotEmpty) return season.episodes.last;
    }
    return null;
  }

  (Season, Episode)? locateEpisode(String episodeId) {
    for (final Season season in seasons) {
      final Episode? episode = season.episodeById(episodeId);
      if (episode != null) return (season, episode);
    }
    return null;
  }

  /// Épisode suivant (pour la lecture automatique) :
  /// même saison d'abord, puis première saison suivante.
  Episode? nextEpisodeOf(Episode episode) {
    for (final Season season in seasons) {
      final int index = season.episodes.indexWhere((Episode e) => e.id == episode.id);
      if (index == -1) continue;
      if (index + 1 < season.episodes.length) return season.episodes[index + 1];
    }
    for (int i = 0; i < seasons.length - 1; i++) {
      if (seasons[i].episodes.isNotEmpty && seasons[i].episodes.last.id == episode.id && seasons[i + 1].episodes.isNotEmpty) {
        return seasons[i + 1].episodes.first;
      }
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
          for (final Episode episode in season.episodes)
            for (final quality in episode.qualities) quality.quality,
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
        rating: rating,
        status: status,
        languages: languages,
        episodeDurationMin: episodeDurationMin,
        source: source,
        popularity: popularity,
        followers: followers,
        isFollowing: isFollowing ?? this.isFollowing,
        canonicalTitle: canonicalTitle,
        originalTitle: originalTitle,
        alternativeTitles: alternativeTitles,
        aliases: aliases,
        metadataStatus: metadataStatus,
        metadataSource: metadataSource,
        metadataUpdatedAt: metadataUpdatedAt,
        metadataCandidates: metadataCandidates,
        totalEpisodesDeclared: totalEpisodesDeclared,
        seasonCountDeclared: seasonCountDeclared,
        episodeDurationMinDeclared: episodeDurationMinDeclared,
        posterUrl: posterUrl,
        backdropUrl: backdropUrl,
      );
}
