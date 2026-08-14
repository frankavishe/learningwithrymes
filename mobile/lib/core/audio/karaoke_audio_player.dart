import 'package:just_audio/just_audio.dart';

/// The subset of playback behavior [KaraokePlayerScreen] needs
/// (`specs/10-screen-karaoke-player.md`), abstracted behind an interface so
/// widget tests can inject a fake instead of driving real `just_audio`
/// platform channels/network fetches — mirrors [ApiClient]'s injectable
/// `http.Client` for the same reason.
abstract class KaraokeAudioPlayer {
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;

  /// Loads [url] and, if [position] is given, seeks there once loaded —
  /// used when switching stems so playback position survives the source
  /// change (`UI-PLAYER-003`'s acceptance criterion).
  Future<void> setUrl(String url, {Duration? position});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
}

/// Real implementation, delegating to the app-wide `just_audio` singleton
/// (`audioPlayerProvider`, Phase 7).
class JustAudioKaraokePlayer implements KaraokeAudioPlayer {
  JustAudioKaraokePlayer(this._player);

  final AudioPlayer _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<void> setUrl(String url, {Duration? position}) async {
    await _player.setUrl(url);
    if (position != null) await _player.seek(position);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);
}
