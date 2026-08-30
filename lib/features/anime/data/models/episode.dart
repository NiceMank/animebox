import 'video_quality.dart';

/// Un épisode d'une saison.
///
/// Les qualités disponibles seront, à terme, alimentées par le moteur de
/// synchronisation Telegram (plusieurs publications = plusieurs qualités).
class Episode {
  const Episode({
    required this.id,
    required this.number,
    this.title,
    required this.qualities,
  });

  final String id;
  final int number;
  final String? title;
  final List<VideoQuality> qualities;

  String get label => 'Épisode $number';
}
