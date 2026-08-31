/// Qualité vidéo d'un épisode.
enum VideoQuality { fhd, hd, sd, low }

extension VideoQualityX on VideoQuality {
  String get label => switch (this) {
        VideoQuality.fhd => '1080p',
        VideoQuality.hd => '720p',
        VideoQuality.sd => '480p',
        VideoQuality.low => '360p',
      };

  /// Résolution courte affichée dans les options de qualité (FHD, HD, SD).
  String get resolution => switch (this) {
        VideoQuality.fhd => 'FHD',
        VideoQuality.hd => 'HD',
        VideoQuality.sd => 'SD',
        VideoQuality.low => 'SD',
      };

  /// Rang pour le tri (de la meilleure à la moins bonne qualité).
  int get sortRank => switch (this) {
        VideoQuality.fhd => 0,
        VideoQuality.hd => 1,
        VideoQuality.sd => 2,
        VideoQuality.low => 3,
      };

  static VideoQuality? fromLabel(String label) => switch (label) {
        '1080p' => VideoQuality.fhd,
        '720p' => VideoQuality.hd,
        '480p' => VideoQuality.sd,
        '360p' => VideoQuality.low,
        _ => null,
      };
}
