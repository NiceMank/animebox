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

/// Préférence de qualité de l'utilisateur (prompt 8, règle 6).
///
/// `auto` sélectionne la meilleure qualité réellement disponible.
enum QualityPreference { auto, uhd, qhd, fhd, hd, sd, low }

extension QualityPreferenceX on QualityPreference {
  String get label => switch (this) {
        QualityPreference.auto => 'Auto',
        QualityPreference.uhd => '2160p',
        QualityPreference.qhd => '1440p',
        QualityPreference.fhd => '1080p',
        QualityPreference.hd => '720p',
        QualityPreference.sd => '480p',
        QualityPreference.low => '360p',
      };

  /// Valeur vidéo correspondante (null pour Auto — dépend du catalogue).
  VideoQuality? get target => switch (this) {
        QualityPreference.auto => null,
        QualityPreference.uhd || QualityPreference.qhd => VideoQuality.fhd,
        QualityPreference.fhd => VideoQuality.fhd,
        QualityPreference.hd => VideoQuality.hd,
        QualityPreference.sd => VideoQuality.sd,
        QualityPreference.low => VideoQuality.low,
      };

  static QualityPreference fromName(String? name) {
    for (final QualityPreference value in QualityPreference.values) {
      if (value.name == name) return value;
    }
    return QualityPreference.auto;
  }
}
