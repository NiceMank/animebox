import 'video_quality.dart';

/// Préférences de lecture de l'utilisateur (locales pour cette étape).
class PlaybackSettings {
  const PlaybackSettings({
    this.autoPlayNext = true,
    this.resumeFromLastPosition = true,
    this.preferredQuality = QualityPreference.auto,
    this.subtitlesEnabled = true,
  });

  /// Lecture automatique de l'épisode suivant.
  final bool autoPlayNext;

  /// Reprise à la dernière position enregistrée.
  final bool resumeFromLastPosition;

  /// Qualité préférée (utilisée à l'ouverture de l'écran de qualité).
  /// Auto = la meilleure qualité réellement disponible.
  final QualityPreference preferredQuality;

  final bool subtitlesEnabled;

  PlaybackSettings copyWith({
    bool? autoPlayNext,
    bool? resumeFromLastPosition,
    QualityPreference? preferredQuality,
    bool? subtitlesEnabled,
  }) =>
      PlaybackSettings(
        autoPlayNext: autoPlayNext ?? this.autoPlayNext,
        resumeFromLastPosition: resumeFromLastPosition ?? this.resumeFromLastPosition,
        preferredQuality: preferredQuality ?? this.preferredQuality,
        subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      );
}
