import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Base URL for the NestJS backend (`specs/03-auth-api.md`, global `/api`
/// prefix). `10.0.2.2` is the Android emulator's alias for the host
/// machine's `localhost` — matches `backend/.env.example`'s default
/// `PORT=3000` and assumes the Phase 0 `docker-compose.yml` stack plus
/// `npm run start` are running on the host. See
/// `network_security_config.xml` for the matching cleartext allowance.
const _defaultBaseUrl = 'http://10.0.2.2:3000/api';

/// Mirrors `AuthResult['user']` from `backend/src/auth/auth.service.ts`.
class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
      );
}

/// Mirrors `AuthResult` from `backend/src/auth/auth.service.ts` — the shared
/// response shape of `POST /api/auth/register` and `POST /api/auth/login`.
class AuthResult {
  const AuthResult({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        accessToken: json['accessToken'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}

/// Mirrors `GenerateSongResult` from `backend/src/songs/songs.service.ts` —
/// the `202` response body of `POST /api/songs/generate`. Confirms the job
/// was enqueued (`AI-005`); it says nothing about the song being ready yet.
class GenerateSongResult {
  const GenerateSongResult({required this.promptId, required this.jobId});

  final String promptId;
  final String jobId;

  factory GenerateSongResult.fromJson(Map<String, dynamic> json) => GenerateSongResult(
        promptId: json['promptId'] as String,
        jobId: json['jobId'] as String,
      );
}

/// Mirrors `backend/src/songs/entities/song.entity.ts` (`DB-003`) — a
/// completed (or in-progress) generation. Used by both `GET /api/songs`
/// (list) and `GET /api/songs/:id` (detail, `API-002`), which return the
/// same shape.
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.generatedLyrics,
    required this.audioFileUrl,
    this.vocalStemUrl,
    this.beatStemUrl,
    this.durationSeconds,
  });

  final String id;
  final String title;
  final String generatedLyrics;
  final String audioFileUrl;
  final String? vocalStemUrl;
  final String? beatStemUrl;
  final int? durationSeconds;

  factory Song.fromJson(Map<String, dynamic> json) => Song(
        id: json['id'] as String,
        title: json['title'] as String,
        generatedLyrics: json['generatedLyrics'] as String,
        audioFileUrl: json['audioFileUrl'] as String,
        vocalStemUrl: json['vocalStemUrl'] as String?,
        beatStemUrl: json['beatStemUrl'] as String?,
        durationSeconds: json['durationSeconds'] as int?,
      );
}

/// Thrown by [ApiClient] on a non-2xx response or an unreachable server.
/// [message] is meant to be shown to the user directly — [AuthScreen] relies
/// on this to satisfy `UI-AUTH-001`'s "invalid credentials show an inline
/// error, not a crash" acceptance criterion.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin HTTP client for the auth endpoints (`AUTH-001`/`AUTH-002`). Scoped to
/// auth for now; later phases can add methods here (or a sibling client) as
/// more of the backend API gets consumed from the app.
class ApiClient {
  // `_baseUrl` keeps the field private while still exposing a conventional
  // public `baseUrl` named parameter.
  ApiClient({String baseUrl = _defaultBaseUrl, http.Client? client})
      // ignore: prefer_initializing_formals
      : _baseUrl = baseUrl,
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) {
    return _postAuth('/auth/register', {
      'name': name,
      'email': email,
      'password': password,
    });
  }

  Future<AuthResult> login({required String email, required String password}) {
    return _postAuth('/auth/login', {'email': email, 'password': password});
  }

  /// `API-006` — requires a signed-in [token] (JWT, `AUTH-003` guards the
  /// route). The pipeline itself runs async (`AI-005`); a successful return
  /// here just means the job was enqueued, not that the song is ready yet
  /// (`UI-BUILDER-005`).
  Future<GenerateSongResult> generateSong({
    required String token,
    required String text,
    required String genre,
    required String mood,
    String? subject,
  }) async {
    final body = <String, dynamic>{'text': text, 'genre': genre, 'mood': mood};
    if (subject != null && subject.isNotEmpty) body['subject'] = subject;

    final decoded = await _postJson(
      '/songs/generate',
      body,
      headers: {'Authorization': 'Bearer $token'},
    );
    return GenerateSongResult.fromJson(decoded);
  }

  /// `API-001` — the caller's songs, newest first.
  Future<List<Song>> getSongs({required String token}) {
    return _getJson(
      '/songs',
      token: token,
      decode: (decoded) => (decoded as List<dynamic>)
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `API-002` — the karaoke player screen's data source (`UI-PLAYER-001`..
  /// `003`). A song owned by another user (or missing) comes back as a 404
  /// `ApiException`, never leaked as a distinct 403 (`AUTH-003`).
  Future<Song> getSong({required String token, required String id}) {
    return _getJson('/songs/$id', token: token, decode: (decoded) => Song.fromJson(decoded as Map<String, dynamic>));
  }

  Future<T> _getJson<T>(
    String path, {
    required String token,
    required T Function(dynamic decoded) decode,
  }) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse('$_baseUrl$path'), headers: {'Authorization': 'Bearer $token'});
    } catch (e) {
      throw ApiException('Could not reach the server. Check your connection and try again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_extractMessage(_decodeBody(response.body), response.statusCode), statusCode: response.statusCode);
    }

    return decode(response.body.isEmpty ? null : jsonDecode(response.body));
  }

  Future<AuthResult> _postAuth(String path, Map<String, dynamic> body) async {
    final decoded = await _postJson(path, body);
    return AuthResult.fromJson(decoded);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: {'Content-Type': 'application/json', ...?headers},
        body: jsonEncode(body),
      );
    } catch (e) {
      throw ApiException('Could not reach the server. Check your connection and try again.');
    }

    final decoded = _decodeBody(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_extractMessage(decoded, response.statusCode), statusCode: response.statusCode);
    }

    return decoded;
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  // Nest's default exception filter body is `{ message, error, statusCode }`,
  // where `message` is a plain string for thrown HttpExceptions (e.g.
  // AUTH-002's "Invalid email or password") or a string array for
  // ValidationPipe failures.
  String _extractMessage(Map<String, dynamic> body, int statusCode) {
    final message = body['message'];
    if (message is String && message.isNotEmpty) return message;
    if (message is List && message.isNotEmpty) return message.join(', ');
    return 'Request failed ($statusCode)';
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
