import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rhythmnotes_app/core/auth/auth_session_providers.dart';
import 'package:rhythmnotes_app/core/network/api_client.dart';
import 'package:rhythmnotes_app/core/storage/secure_storage_service.dart';
import 'package:rhythmnotes_app/features/karaoke_player/karaoke_player_screen.dart';
import 'package:rhythmnotes_app/features/karaoke_player/song_list_screen.dart';

/// Widget tests for the temporary [SongListScreen] — Phase 10's only way to
/// reach [KaraokePlayerScreen] before Phase 11's real library screen exists.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{'jwt_token': 'stored-jwt'};

  setUp(() {
    store
      ..clear()
      ..['jwt_token'] = 'stored-jwt';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (MethodCall call) async {
      switch (call.method) {
        case 'write':
          store[call.arguments['key'] as String] = call.arguments['value'] as String;
          return null;
        case 'read':
          return store[call.arguments['key'] as String];
        case 'delete':
          store.remove(call.arguments['key'] as String);
          return null;
        default:
          throw MissingPluginException();
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  Future<void> pumpScreen(WidgetTester tester, http.Client mockHttpClient) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://test.local/api', client: mockHttpClient)),
          secureStorageServiceProvider
              .overrideWithValue(SecureStorageService(storage: const FlutterSecureStorage())),
        ],
        child: const MaterialApp(home: Scaffold(body: SongListScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders each song from GET /api/songs', (tester) async {
    await pumpScreen(
      tester,
      MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'id': 'song-1',
              'title': 'Newton in Rhythm',
              'generatedLyrics': '[Verse 1]\nline',
              'audioFileUrl': 'http://test.local/songs/song-1.mp3',
              'durationSeconds': 60,
            },
          ]),
          200,
        );
      }),
    );

    expect(find.text('Newton in Rhythm'), findsOneWidget);
  });

  testWidgets('shows an empty-state message with no songs', (tester) async {
    await pumpScreen(tester, MockClient((request) async => http.Response('[]', 200)));

    expect(find.text('No songs yet — generate one from the New song tab.'), findsOneWidget);
  });

  testWidgets('tapping a song pushes the karaoke player screen', (tester) async {
    await pumpScreen(
      tester,
      MockClient((request) async {
        if (request.url.path == '/api/songs') {
          return http.Response(
            jsonEncode([
              {
                'id': 'song-1',
                'title': 'Newton in Rhythm',
                'generatedLyrics': '[Verse 1]\nline',
                'audioFileUrl': 'http://test.local/songs/song-1.mp3',
                'durationSeconds': 60,
              },
            ]),
            200,
          );
        }
        // The pushed KaraokePlayerScreen re-fetches by id (API-002); no real
        // audio playback is exercised here since karaokeAudioPlayerProvider
        // isn't overridden — just confirming navigation happened.
        return http.Response('{}', 500);
      }),
    );

    await tester.tap(find.text('Newton in Rhythm'));
    // A single pump() leaves the pushed route's page-transition animation
    // in flight, which find.byType (skipOffstage: true, the default)
    // doesn't consider "onstage" yet — settle it first.
    await tester.pumpAndSettle();

    expect(find.byType(KaraokePlayerScreen), findsOneWidget);
  });
}
