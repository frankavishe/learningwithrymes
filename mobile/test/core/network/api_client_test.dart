import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rhythmnotes_app/core/network/api_client.dart';

/// Unit tests for [ApiClient] against `backend/src/auth`'s actual response
/// shapes (`AUTH-001`/`AUTH-002`), using `http`'s [MockClient] instead of a
/// live server.
void main() {
  group('register', () {
    test('parses a successful response into an AuthResult', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          expect(request.url.toString(), 'http://test.local/api/auth/register');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body, {'name': 'Ada', 'email': 'ada@example.com', 'password': 'password123'});

          return http.Response(
            jsonEncode({
              'accessToken': 'jwt.token.here',
              'user': {
                'id': 'user-1',
                'name': 'Ada',
                'email': 'ada@example.com',
                'createdAt': '2026-08-11T00:00:00.000Z',
              },
            }),
            201,
          );
        }),
      );

      final result = await client.register(name: 'Ada', email: 'ada@example.com', password: 'password123');

      expect(result.accessToken, 'jwt.token.here');
      expect(result.user.id, 'user-1');
      expect(result.user.name, 'Ada');
      expect(result.user.email, 'ada@example.com');
    });

    test('throws ApiException with the server message on a duplicate email (409)', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'statusCode': 409, 'message': 'Email is already registered', 'error': 'Conflict'}),
            409,
          );
        }),
      );

      await expectLater(
        client.register(name: 'Ada', email: 'ada@example.com', password: 'password123'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', 'Email is already registered'),
        ),
      );
    });

    test('joins a ValidationPipe array message into one string (400)', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'statusCode': 400,
              'message': ['email must be an email', 'password must be longer than 8 characters'],
              'error': 'Bad Request',
            }),
            400,
          );
        }),
      );

      await expectLater(
        client.register(name: 'Ada', email: 'not-an-email', password: 'short'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'email must be an email, password must be longer than 8 characters',
          ),
        ),
      );
    });
  });

  group('login', () {
    test('throws ApiException on invalid credentials (401)', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          expect(request.url.toString(), 'http://test.local/api/auth/login');
          return http.Response(
            jsonEncode({'statusCode': 401, 'message': 'Invalid email or password', 'error': 'Unauthorized'}),
            401,
          );
        }),
      );

      await expectLater(
        client.login(email: 'ada@example.com', password: 'wrong-password'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Invalid email or password'),
        ),
      );
    });

    test('wraps a transport failure as an ApiException instead of throwing raw', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async => throw const SocketExceptionStub()),
      );

      await expectLater(
        client.login(email: 'ada@example.com', password: 'password123'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('generateSong', () {
    test('sends the bearer token and body, and parses a 202 response (API-006)', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          expect(request.url.toString(), 'http://test.local/api/songs/generate');
          expect(request.headers['Authorization'], 'Bearer jwt.token.here');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body, {
            'text': 'E = mc^2',
            'genre': 'Synthwave',
            'mood': 'Calm Study Vibe',
            'subject': 'Physics',
          });

          return http.Response(
            jsonEncode({'promptId': 'prompt-1', 'jobId': 'job-1'}),
            202,
          );
        }),
      );

      final result = await client.generateSong(
        token: 'jwt.token.here',
        text: 'E = mc^2',
        genre: 'Synthwave',
        mood: 'Calm Study Vibe',
        subject: 'Physics',
      );

      expect(result.promptId, 'prompt-1');
      expect(result.jobId, 'job-1');
    });

    test('omits subject from the body when not provided', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.containsKey('subject'), isFalse);
          return http.Response(jsonEncode({'promptId': 'prompt-1', 'jobId': 'job-1'}), 202);
        }),
      );

      await client.generateSong(token: 'jwt.token.here', text: 'notes', genre: 'Lo-Fi', mood: 'Calm Study Vibe');
    });

    test('throws ApiException with the server message on a 401', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          return http.Response(jsonEncode({'statusCode': 401, 'message': 'Unauthorized'}), 401);
        }),
      );

      await expectLater(
        client.generateSong(token: 'bad-token', text: 'notes', genre: 'Lo-Fi', mood: 'Calm Study Vibe'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('getSongs', () {
    test('sends the bearer token and parses the list (API-001)', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), 'http://test.local/api/songs');
          expect(request.headers['Authorization'], 'Bearer jwt.token.here');

          return http.Response(
            jsonEncode([
              {
                'id': 'song-1',
                'title': 'Newton in Rhythm',
                'generatedLyrics': '[Verse 1]\nline one',
                'audioFileUrl': 'http://minio.local/songs/song-1.mp3',
                'vocalStemUrl': null,
                'beatStemUrl': null,
                'durationSeconds': 60,
              },
            ]),
            200,
          );
        }),
      );

      final songs = await client.getSongs(token: 'jwt.token.here');

      expect(songs, hasLength(1));
      expect(songs.single.id, 'song-1');
      expect(songs.single.title, 'Newton in Rhythm');
      expect(songs.single.vocalStemUrl, isNull);
      expect(songs.single.durationSeconds, 60);
    });

    test('throws ApiException on a non-2xx response', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          return http.Response(jsonEncode({'message': 'Unauthorized'}), 401);
        }),
      );

      await expectLater(
        client.getSongs(token: 'bad-token'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('getSong', () {
    test('sends the bearer token and parses the detail (API-002)', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), 'http://test.local/api/songs/song-1');
          expect(request.headers['Authorization'], 'Bearer jwt.token.here');

          return http.Response(
            jsonEncode({
              'id': 'song-1',
              'title': 'Newton in Rhythm',
              'generatedLyrics': '[Verse 1]\nline one',
              'audioFileUrl': 'http://minio.local/songs/song-1.mp3',
              'vocalStemUrl': 'http://minio.local/songs/song-1-vocals.mp3',
              'beatStemUrl': null,
              'durationSeconds': 60,
            }),
            200,
          );
        }),
      );

      final song = await client.getSong(token: 'jwt.token.here', id: 'song-1');

      expect(song.id, 'song-1');
      expect(song.vocalStemUrl, 'http://minio.local/songs/song-1-vocals.mp3');
      expect(song.beatStemUrl, isNull);
    });

    test('throws a 404 ApiException for another user\'s song', () async {
      final client = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          return http.Response(jsonEncode({'message': 'Song not found'}), 404);
        }),
      );

      await expectLater(
        client.getSong(token: 'jwt.token.here', id: 'not-mine'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Song not found'),
        ),
      );
    });
  });
}

/// Stand-in for `dart:io`'s `SocketException` — avoids importing `dart:io`
/// just for this one throw in a client-agnostic test.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
