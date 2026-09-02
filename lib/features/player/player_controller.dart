import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Piste sélectionnable d'un média réel (sous-titres ou audio).
class PlayerTrack {
  const PlayerTrack({required this.id, this.title, this.language});

  final String id;
  final String? title;
  final String? language;

  String get label =>
      (title != null && title!.isNotEmpty ? title! : (language?.toUpperCase() ?? 'Piste $id'));
}

/// Contrôleur de lecture RÉELLE (aucune simulation).
///
/// L'écran ne dépend que de cette interface : l'implémentation de
/// production s'appuie sur media_kit (libmpv — MKV, sous-titres et pistes
/// audio embarqués réellement supportés) ; les tests injectent un double.
abstract class PlayerController extends ChangeNotifier {
  /// Surface vidéo à insérer dans l'arbre (null si lecture audio seule).
  Widget? buildVideo(BuildContext context);

  bool get isPlaying;
  Duration get position;
  Duration get duration;
  double get volume;

  /// Chargement réel du fichier local [path] (complet ou partiel TDLib).
  /// Lève une exception si le format n'est pas supporté par le lecteur.
  Future<void> open(String path, {Duration? initialPosition});

  Future<void> play();
  Future<void> pause();
  Future<void> togglePlay();
  Future<void> seek(Duration position);
  Future<void> seekRelative(Duration delta);
  Future<void> setVolume(double value);

  /// Pistes réellement présentes dans le fichier.
  List<PlayerTrack> get subtitleTracks;
  List<PlayerTrack> get audioTracks;
  String? get currentSubtitleTrackId;

  Future<void> setSubtitleTrack(String? trackId); // null → désactivés
  Future<void> setAudioTrack(String trackId);

  /// Événements de position (progression réelle — sauvegarde).

  /// L'événement « média terminé » réel.
  Stream<void> get onCompleted;

  bool get isInitialized;
}

/// Implémentation media_kit — lecture locale réelle.
class MediaKitPlayerController extends PlayerController {
  MediaKitPlayerController() {
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _videoController = VideoController(_player);
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      _player.stream.position.listen((Duration value) {
        _position = value;
        notifyListeners();
      }),
      _player.stream.duration.listen((Duration value) {
        _duration = value;
        notifyListeners();
      }),
      _player.stream.playing.listen((bool value) {
        _playing = value;
        notifyListeners();
      }),
      _player.stream.volume.listen((double value) {
        _volume = value;
        notifyListeners();
      }),
      _player.stream.tracks.listen((Tracks tracks) {
        _subtitleTracks = _mapSubtitles(tracks.subtitle);
        _audioTracks = _mapAudios(tracks.audio);
        notifyListeners();
      }),
      _player.stream.track.listen((Track track) {
        _currentSubtitleId = track.subtitle.id;
        notifyListeners();
      }),
      _player.stream.completed.listen((bool completed) {
        if (completed) _completed.add(null);
      }),
    ]);
  }

  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final StreamController<void> _completed = StreamController<void>.broadcast();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _volume = 100;
  bool _initialized = false;
  List<PlayerTrack> _subtitleTracks = const <PlayerTrack>[];
  List<PlayerTrack> _audioTracks = const <PlayerTrack>[];
  String? _currentSubtitleId;

  @override
  Widget buildVideo(BuildContext context) =>
      Video(controller: _videoController, controls: NoVideoControls);

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlaying => _playing;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  double get volume => _volume;

  @override
  List<PlayerTrack> get subtitleTracks => _subtitleTracks;

  @override
  List<PlayerTrack> get audioTracks => _audioTracks;

  @override
  String? get currentSubtitleTrackId => _currentSubtitleId;

  @override
  Stream<void> get onCompleted => _completed.stream;

  @override
  Future<void> open(String path, {Duration? initialPosition}) async {
    // Lecture RÉELLE du fichier (complet ou partiel contigu).
    await _player.open(Media(path));
    _initialized = true;
    if (initialPosition != null && initialPosition > Duration.zero) {
      // La reprise attend que la durée réelle soit connue (média chargé).
      final Duration realDuration = await _player.stream.duration
          .firstWhere((Duration d) => d > Duration.zero)
          .timeout(const Duration(seconds: 15), onTimeout: () => Duration.zero);
      if (realDuration > Duration.zero) {
        final Duration target =
            initialPosition >= realDuration - const Duration(seconds: 2) ? Duration.zero : initialPosition;
        await _player.seek(target);
        _position = target;
        notifyListeners();
      }
    }
    notifyListeners();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> togglePlay() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> seekRelative(Duration delta) async {
    final Duration target = _position + delta;
    await _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> setVolume(double value) => _player.setVolume(value.clamp(0, 100));

  List<PlayerTrack> _mapSubtitles(List<SubtitleTrack> tracks) => <PlayerTrack>[
        for (final SubtitleTrack track in tracks)
          if (track.id != 'auto' && track.id != 'no')
            PlayerTrack(id: track.id, title: track.title, language: track.language),
      ];

  List<PlayerTrack> _mapAudios(List<AudioTrack> tracks) => <PlayerTrack>[
        for (final AudioTrack track in tracks)
          PlayerTrack(id: track.id, title: track.title, language: track.language),
      ];

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    if (trackId == null || trackId.isEmpty) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      _currentSubtitleId = null;
    } else {
      await _player.setSubtitleTrack(SubtitleTrack(trackId, null, null));
      _currentSubtitleId = trackId;
    }
    notifyListeners();
  }

  @override
  Future<void> setAudioTrack(String trackId) => _player.setAudioTrack(AudioTrack(trackId, null, null));

  @override
  void dispose() {
    for (final StreamSubscription<dynamic> sub in _subscriptions) {
      sub.cancel();
    }
    _completed.close();
    _player.dispose();
    super.dispose();
  }
}

/// Crée un contrôleur media_kit si la plateforme le permet (initialisation
/// unique). Renvoie null quand la lecture réelle est impossible — l'écran
/// affiche alors le repli honnête (jamais un faux lecteur).
PlayerController? tryCreatePlayerController() {
  try {
    MediaKit.ensureInitialized();
    return MediaKitPlayerController();
  } catch (_) {
    return null;
  }
}
