import 'package:flutter/foundation.dart';

import '../../../anime/data/models/anime.dart';
import '../../../anime/data/models/episode.dart';
import '../../../anime/data/models/episode_quality.dart';
import '../../../anime/data/models/season.dart';
import '../../../anime/data/models/video_quality.dart';

/// Représentation d'une publication brute (équivalent d'un message Telegram).
///
/// Le futur moteur d'analyse produira ces objets ; pour cette étape ils
/// proviennent uniquement de données mockées.
class RawPublication {
  const RawPublication({
    required this.channelUsername,
    required this.animeTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.qualityLabel,
    required this.language,
    this.subtitles = 'FR',
    this.sizeBytes,
    this.messageId,
    this.messageLink,
  });

  final String channelUsername;
  final String animeTitle;
  final int seasonNumber;
  final int episodeNumber;
  final String qualityLabel;
  final String language;
  final String subtitles;
  final int? sizeBytes;

  /// Réservés au moteur Telegram réel (non utilisés à ce stade).
  final int? messageId;
  final String? messageLink;

  /// Clé de regroupement : même animé + même saison + même épisode
  /// = même épisode, quelle que soit la qualité.
  String get groupingKey => '${animeTitle.toLowerCase()}|s$seasonNumber|e$episodeNumber';

  String get summary => '$animeTitle S${seasonNumber.toString().padLeft(2, '0')}'
      'E${episodeNumber.toString().padLeft(2, '0')} $qualityLabel';
}

/// Regroupe les publications brutes en épisodes uniques.
///
/// Plusieurs publications décrivant le même animé/saison/épisode dans des
/// qualités différentes produisent UN SEUL épisode doté de toutes les
/// qualités — jamais d'épisodes dupliqués.
class EpisodeGroupingService extends ChangeNotifier {
  EpisodeGroupingService();

  /// Publications brutes en attente d'analyse (mock).
  List<RawPublication> _pending = const [];

  List<RawPublication> get pendingPublications => List.unmodifiable(_pending);

  /// Ajoute une publication (simulation d'une détection).
  void addPublication(RawPublication publication) {
    _pending = [..._pending, publication];
    notifyListeners();
  }

  void clearPending() {
    _pending = const [];
    notifyListeners();
  }

  /// Regroupe des publications vers une structure animé → saisons → épisodes.
  ///
  /// Le résultat est un nouveau graphe d'objets [Anime] contenant les épisodes
  /// construits à partir des publications fournies (sans écraser le
  /// catalogue : les épisodes restants du catalogue sont conservés).
  List<Anime> group(List<RawPublication> publications) {
    // Étape 1 : indexer les publications par clé de regroupement.
    final Map<String, List<RawPublication>> groups = {};
    for (final RawPublication publication in publications) {
      groups.putIfAbsent(publication.groupingKey, () => []).add(publication);
    }

    // Étape 2 : construire un animé par titre rencontré.
    final Map<String, AnimeBuilder> builders = {};
    for (final MapEntry<String, List<RawPublication>> entry in groups.entries) {
      final RawPublication sample = entry.value.first;
      final AnimeBuilder builder = builders.putIfAbsent(sample.animeTitle, () => AnimeBuilder(sample.animeTitle));
      builder.addGroup(sample.seasonNumber, sample.episodeNumber, entry.value);
    }

    return [for (final AnimeBuilder builder in builders.values) builder.build()];
  }

  /// Fusionne les épisodes issus des publications dans le catalogue,
  /// en conservant les épisodes existants (métadonnées riches du mock).
  ///
  /// Retourne la liste des identifiants d'épisodes nouvellement créés.
  List<String> mergeIntoCatalog(List<Anime> grouped, List<Anime> catalog) {
    final List<String> created = [];
    for (final Anime anime in grouped) {
      final Anime? existing = catalog.where((Anime candidate) => candidate.id == _idOf(anime.title)).firstOrNull;
      if (existing == null) continue;
      final int lastSeasonNumber = existing.seasons.isEmpty ? 0 : existing.seasons.map((s) => s.number).reduce((a, b) => a > b ? a : b);
      for (final Season season in anime.seasons) {
        if (season.number <= lastSeasonNumber) continue;
        final Episode newEpisode = season.episodes.first;
        existing.seasons.add(Season(
          id: '${existing.id}-s${season.number}',
          number: season.number,
          episodes: [newEpisode],
        ));
        created.add(newEpisode.id);
      }
    }
    return created;
  }

  String _idOf(String title) {
    const String accented = 'áàâäãåéèêëíìîïóòôöõúùûüçñ ';
    const String plain = 'aaaaaaeeeeiiiiooooouuuucn-';
    final StringBuffer buffer = StringBuffer();
    for (final int rune in title.toLowerCase().runes) {
      final String character = String.fromCharCode(rune);
      final int index = accented.indexOf(character);
      buffer.write(index >= 0 ? plain[index] : character);
    }
    return buffer.toString();
  }
}

/// Construit progressivement un [Anime] à partir de groupes de publications.
class AnimeBuilder {
  AnimeBuilder(this.title);

  final String title;
  final Map<int, Map<int, List<RawPublication>>> _seasons = {};

  void addGroup(int seasonNumber, int episodeNumber, List<RawPublication> publications) {
    _seasons.putIfAbsent(seasonNumber, () => {}).putIfAbsent(episodeNumber, () => []).addAll(publications);
  }

  Anime build() {
    // Les publications mockées n'embarquent pas de date : l'épisode détecté
    // est horodaté à sa détection.
    final DateTime detectedAt = DateTime.now();
    final List<Season> seasons = [
      for (final MapEntry<int, Map<int, List<RawPublication>>> seasonEntry in _seasons.entries)
        Season(
          id: 'detected-s${seasonEntry.key}',
          number: seasonEntry.key,
          episodes: [
            for (final MapEntry<int, List<RawPublication>> episodeEntry in seasonEntry.value.entries)
              Episode(
                id: 'detected-s${seasonEntry.key}-e${episodeEntry.key}',
                number: episodeEntry.key,
                title: null,
                thumbnail: '',
                date: detectedAt,
                isNew: true,
                qualities: _qualitiesFrom(episodeEntry.value),
              ),
          ],
        ),
    ];
    return Anime(
      id: title,
      title: title,
      posterAsset: '',
      backdropAsset: '',
      description: '',
      genres: const [],
      year: detectedAt.year,
      seasons: seasons,
      source: 'Détection',
      status: AnimeStatus.ongoing,
    );
  }

  List<EpisodeQuality> _qualitiesFrom(List<RawPublication> publications) {
    final Map<VideoQuality, RawPublication> byQuality = {};
    for (final RawPublication publication in publications) {
      final VideoQuality? quality = VideoQualityX.fromLabel(publication.qualityLabel);
      if (quality == null) continue;
      // On conserve la plus grande taille par qualité.
      final RawPublication? previous = byQuality[quality];
      if (previous == null || (publication.sizeBytes ?? 0) > (previous.sizeBytes ?? 0)) {
        byQuality[quality] = publication;
      }
    }
    final List<VideoQuality> ordered = byQuality.keys.toList()
      ..sort((a, b) => a.sortRank.compareTo(b.sortRank));
    return [
      for (final VideoQuality quality in ordered)
        EpisodeQuality(
          id: 'detected-${quality.label}',
          quality: quality,
          resolution: quality.resolution,
          size: byQuality[quality]!.sizeBytes ?? 0,
          language: byQuality[quality]!.language,
          subtitles: byQuality[quality]!.subtitles,
        ),
    ];
  }
}
