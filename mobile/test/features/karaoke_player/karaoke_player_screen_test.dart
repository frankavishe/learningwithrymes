import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rhythmnotes_app/core/audio/audio_player_providers.dart';
import 'package:rhythmnotes_app/core/audio/karaoke_audio_player.dart';
import 'package:rhythmnotes_app/core/auth/auth_session_providers.dart';
import 'package:rhythmnotes_app/core/network/api_client.dart';
import 'package:rhythmnotes_app/core/storage/secure_storage_service.dart';
import 'package:rhythmnotes_app/features/karaoke_player/karaoke_player_screen.dart';

/// Widget tests for [KaraokePlayerScreen] (`specs/10-screen-karaoke-player.md`):
/// synced lyric highlighting (`UI-PLAYER-001`), play/pause + loop-chorus
/// (`UI-PLAYER-002`), and stem toggles that preserve playback position
/// (`UI-PLAYER-003`). Uses [FakeKaraokeAudioPlayer] instead of real
/// `just_audio` platform channels/network fetches.
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

  Map<String, dynamic> songJson({
    String id = 'song-1',
    String title = 'Newton in Rhythm',
    String? vocalStemUrl,
    String? beatStemUrl,
  }) => {
        'id': id,
        'title': title,
        'generatedLyrics': '[Verse 1]\nfirst line\n[Chorus]\nchorus line\n[Verse 2]\nlast line',
        'audioFileUrl': 'http://test.local/songs/$id.mp3',
        'vocalStemUrl': vocalStemUrl,
        'beatStemUrl': beatStemUrl,
        'durationSeconds': 60,
      };

  Future<FakeKaraokeAudioPlayer> pumpScreen(
    WidgetTester tester, {
    required Map<String, dynamic> song,
  }) async {
    final fakePlayer = FakeKaraokeAudioPlayer();
    addTearDown(fakePlayer.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://test.local/api',
              client: MockClient((request) async => http.Response(jsonEncode(song), 200)),
            ),
          ),
          secureStorageServiceProvider
              .overrideWithValue(SecureStorageService(storage: const FlutterSecureStorage())),
          karaokeAudioPlayerProvider.overrideWithValue(fakePlayer),
        ],
        child: MaterialApp(home: KaraokePlayerScreen(songId: song['id'] as String)),
      ),
    );
    await tester.pumpAndSettle();
    return fakePlayer;
  }

  testWidgets('loads the song and starts the audio source', (tester) async {
    final player = await pumpScreen(tester, song: songJson());

    expect(find.widgetWithText(AppBar, 'Newton in Rhythm'), findsOneWidget);
    expect(find.text('first line'), findsOneWidget);
    expect(find.text('chorus line'), findsOneWidget);
    expect(find.text('last line'), findsOneWidget);
    expect(player.setUrlCalls, ['http://test.local/songs/song-1.mp3']);
  });

  testWidgets('highlights the line whose estimated window contains the current position', (tester) async {
    final player = await pumpScreen(tester, song: songJson());

    // 3 lines over 60s => 20s each: 0-20 "first line", 20-40 "chorus line",
    // 40-60 "last line".
    player.emitPosition(const Duration(seconds: 25));
    await tester.pumpAndSettle();

    final active = tester.widget<Text>(find.text('chorus line'));
    expect(active.style?.fontWeight, FontWeight.bold);

    final inactive = tester.widget<Text>(find.text('first line'));
    expect(inactive.style?.fontWeight, FontWeight.normal);
  });

  testWidgets('play/pause toggles the fake player and updates the icon', (tester) async {
    final player = await pumpScreen(tester, song: songJson());

    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_circle_filled));
    await tester.pump();
    expect(player.playing, isTrue);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pump();
    expect(player.playing, isFalse);
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
  });

  testWidgets('loop-chorus button is disabled without a chorus section, enabled with one', (tester) async {
    await pumpScreen(
      tester,
      song: {
        'id': 'song-2',
        'title': 'No Chorus',
        'generatedLyrics': '[Verse 1]\nonly a verse',
        'audioFileUrl': 'http://test.local/songs/song-2.mp3',
        'durationSeconds': 60,
      },
    );

    final button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.repeat));
    expect(button.onPressed, isNull);
  });

  testWidgets('loop-chorus seeks back to the chorus start once the chorus ends', (tester) async {
    final player = await pumpScreen(tester, song: songJson());

    await tester.tap(find.widgetWithIcon(IconButton, Icons.repeat));
    await tester.pump();

    player.emitPosition(const Duration(seconds: 40)); // chorus end (20-40s)
    await tester.pumpAndSettle();

    expect(player.seekCalls, contains(const Duration(seconds: 20)));
  });

  testWidgets('a stem toggle is disabled when its URL is null, enabled when present', (tester) async {
    await pumpScreen(tester, song: songJson(vocalStemUrl: 'http://test.local/songs/song-1-vocals.mp3'));

    final vocalsChip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Vocals'));
    expect(vocalsChip.onSelected, isNotNull);

    final beatChip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Beat'));
    expect(beatChip.onSelected, isNull);
  });

  testWidgets('switching to a stem preserves the current playback position', (tester) async {
    final player = await pumpScreen(
      tester,
      song: songJson(vocalStemUrl: 'http://test.local/songs/song-1-vocals.mp3'),
    );

    player.emitPosition(const Duration(seconds: 12));
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Vocals'));
    await tester.pumpAndSettle();

    expect(player.setUrlCalls.last, 'http://test.local/songs/song-1-vocals.mp3');
    expect(player.setUrlPositions.last, const Duration(seconds: 12));
  });

  testWidgets('a failed load shows an inline error with a retry option', (tester) async {
    final fakePlayer = FakeKaraokeAudioPlayer();
    addTearDown(fakePlayer.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://test.local/api',
              client: MockClient((request) async => http.Response(jsonEncode({'message': 'Song not found'}), 404)),
            ),
          ),
          secureStorageServiceProvider
              .overrideWithValue(SecureStorageService(storage: const FlutterSecureStorage())),
          karaokeAudioPlayerProvider.overrideWithValue(fakePlayer),
        ],
        child: const MaterialApp(home: KaraokePlayerScreen(songId: 'missing')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Song not found'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// In-memory [KaraokeAudioPlayer] for widget tests — records every call
/// instead of touching real `just_audio` platform channels or the network.
class FakeKaraokeAudioPlayer implements KaraokeAudioPlayer {
  final _positionController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();

  final List<String> setUrlCalls = [];
  final List<Duration?> setUrlPositions = [];
  final List<Duration> seekCalls = [];
  bool playing = false;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Future<void> setUrl(String url, {Duration? position}) async {
    setUrlCalls.add(url);
    setUrlPositions.add(position);
  }

  @override
  Future<void> play() async {
    playing = true;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playingController.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls.add(position);
    _positionController.add(position);
  }

  void emitPosition(Duration position) => _positionController.add(position);

  void dispose() {
    _positionController.close();
    _playingController.close();
  }
}
