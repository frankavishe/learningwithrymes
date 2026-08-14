import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'karaoke_audio_player.dart';

/// App-wide [AudioPlayer] instance (`MOBILE-003`), created once and disposed
/// with the provider container. Phase 10's karaoke player consumes this
/// rather than constructing its own player, so play/pause state stays
/// singular across the app shell.
final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// [KaraokeAudioPlayer]-typed wrapper around [audioPlayerProvider], for
/// Phase 10's `KaraokePlayerScreen`. Overridden with a fake in widget tests
/// (see `KaraokeAudioPlayer`'s doc comment) instead of exercising real
/// `just_audio` platform channels.
final karaokeAudioPlayerProvider = Provider<KaraokeAudioPlayer>((ref) {
  return JustAudioKaraokePlayer(ref.watch(audioPlayerProvider));
});
