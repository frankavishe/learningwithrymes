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
    final token = await _ref.read(authTokenProvider.future);
    if (token == null) {
      throw StateError('Cannot generate a song while signed out.');
    }
    return _api.generateSong(token: token, text: text, genre: genre, mood: mood, subject: subject);
  }
}

final songsRepositoryProvider = Provider<SongsRepository>((ref) {
  return SongsRepository(ref, ref.watch(apiClientProvider));
});
