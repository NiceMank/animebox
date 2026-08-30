/// Qualité vidéo d'un épisode.
enum VideoQuality { fhd, hd, sd }

extension VideoQualityX on VideoQuality {
  String get label => switch (this) {
        VideoQuality.fhd => '1080p',
        VideoQuality.hd => '720p',
        VideoQuality.sd => '480p',
      };

  static VideoQuality? fromLabel(String label) => switch (label) {
        '1080p' => VideoQuality.fhd,
        '720p' => VideoQuality.hd,
        '480p' => VideoQuality.sd,
        _ => null,
      };
}
