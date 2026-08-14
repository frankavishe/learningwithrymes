import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session_providers.dart';
import '../network/api_client.dart';

/// Bridges the note builder screen and the songs API (`API-006`) for Screen 2
/// (`specs/09-screen-note-builder.md`). Reads the JWT off [authTokenProvider]
/// (Phase 8) rather than taking it as a parameter, so the screen doesn't need
/// to know anything about session storage.
class SongsRepository {
  SongsRepository(this._ref, this._api);

  final Ref _ref;
  final ApiClient _api;

  /// `UI-BUILDER-005` — throws [ApiException] on a request failure. A `null`
  /// token means this got called while signed out, which shouldn't happen:
  /// `app.dart` only renders the note builder behind the auth gate.
  Future<GenerateSongResult> generate({
    required String text,
    required String genre,
    required String mood,
    String? subject,
  }) async {
    final token = await _requireToken();
    return _api.generateSong(token: token, text: text, genre: genre, mood: mood, subject: subject);
  }

  /// `API-001` — backs the temporary flat song list (`SongListScreen`) used
  /// to reach Phase 10's karaoke player; Phase 11 will replace that screen
  /// with the real subject-grouped library but can keep calling this.
  Future<List<Song>> listSongs() async {
    final token = await _requireToken();
    return _api.getSongs(token: token);
  }

  /// `API-002` — the karaoke player screen's data source (`UI-PLAYER-001`..
  /// `003`).
  Future<Song> getSong(String id) async {
    final token = await _requireToken();
    return _api.getSong(token: token, id: id);
  }

  Future<String> _requireToken() async {
    final token = await _ref.read(authTokenProvider.future);
    if (token == null) {
      throw StateError('Cannot call the songs API while signed out.');
    }
    return token;
  }
}

final songsRepositoryProvider = Provider<SongsRepository>((ref) {
  return SongsRepository(ref, ref.watch(apiClientProvider));
});
