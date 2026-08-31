import 'dart:async';

import 'package:flutter/foundation.dart';

/// Contrôleur de lecture simulé (placeholder vidéo).
///
/// Il reproduit l'interface d'un vrai contrôleur de lecture (play/pause,
/// seek, progression temporelle) afin que l'écran du lecteur soit déjà
/// fonctionnel et testable. Lorsque le streaming réel sera branché, ce
/// contrôleur sera remplacé par `video_player` (ou équivalent) sans
/// modifier l'interface du lecteur.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.duration,
    initialPosition = Duration.zero,
    this.onProgress,
    this.onCompleted,
  }) : _position = initialPosition > duration ? duration : initialPosition;

  final Duration duration;
  final ValueChanged<Duration>? onProgress;
  final VoidCallback? onCompleted;

  Duration _position;
  bool _playing = false;
  Timer? _ticker;

  Duration get position => _position;
  bool get isPlaying => _playing;
  bool get isFinished => duration > Duration.zero && _position >= duration;
  double get fraction => duration.inMilliseconds <= 0 ? 0 : (_position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  void play() {
    if (_playing || isFinished) return;
    _playing = true;
    _ticker = Timer.periodic(const Duration(milliseconds: 500), _onTick);
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void togglePlay() => _playing ? pause() : play();

  void seekTo(Duration target) {
    if (duration <= Duration.zero) return;
    _position = target < Duration.zero ? Duration.zero : (target > duration ? duration : target);
    onProgress?.call(_position);
    notifyListeners();
  }

  void seekRelative(Duration delta) => seekTo(_position + delta);

  void _onTick(Timer timer) {
    _position += const Duration(milliseconds: 500);
    if (_position >= duration) {
      _position = duration;
      _playing = false;
      _ticker?.cancel();
      _ticker = null;
      onCompleted?.call();
    }
    onProgress?.call(_position);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
