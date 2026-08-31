import 'episode.dart';

/// Une saison d'un animé.
class Season {
  const Season({
    required this.id,
    required this.number,
    this.title,
    required this.episodes,
    this.specials = const [],
  });

  final String id;
  final int number;
  final String? title;
  final List<Episode> episodes;

  /// Épisodes spéciaux (OAV, récaps…) — présentés dans un onglet dédié.
  final List<Episode> specials;

  int get episodeCount => episodes.length;
  String get label => 'Saison $number';

  Episode? episodeById(String episodeId) {
    for (final Episode episode in [...episodes, ...specials]) {
      if (episode.id == episodeId) return episode;
    }
    return null;
  }
}
