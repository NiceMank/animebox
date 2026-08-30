import 'episode.dart';

/// Une saison d'un animé.
class Season {
  const Season({
    required this.id,
    required this.number,
    this.title,
    required this.episodes,
  });

  final String id;
  final int number;
  final String? title;
  final List<Episode> episodes;

  int get episodeCount => episodes.length;
  String get label => 'Saison $number';
}
