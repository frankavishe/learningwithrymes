import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rhythmnotes_app/core/auth/auth_session_providers.dart';
import 'package:rhythmnotes_app/core/network/api_client.dart';
import 'package:rhythmnotes_app/core/songs/songs_repository.dart';
import 'package:rhythmnotes_app/core/storage/secure_storage_service.dart';

/// Verifies [SongsRepository] reads the persisted JWT (Phase 8) and calls
/// `POST /api/songs/generate` (`API-006`) with it, for Screen 2's submit
/// (`UI-BUILDER-005`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
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
        .setMockMethodCallHandler(channel, null);
  });

  ProviderContainer buildContainer(http.Client mockHttpClient) {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://test.local/api', client: mockHttpClient)),
        secureStorageServiceProvider
            .overrideWithValue(SecureStorageService(storage: const FlutterSecureStorage())),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('sends the stored JWT as the bearer token', () async {
    store['jwt_token'] = 'stored-jwt';
    String? capturedAuthHeader;
    final container = buildContainer(
      MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'promptId': 'prompt-1', 'jobId': 'job-1'}), 202);
      }),
    );

    final result = await container
        .read(songsRepositoryProvider)
        .generate(text: 'notes', genre: 'Lo-Fi', mood: 'Calm Study Vibe');

    expect(capturedAuthHeader, 'Bearer stored-jwt');
    expect(result.promptId, 'prompt-1');
    expect(result.jobId, 'job-1');
  });

  test('a failed request rethrows ApiException', () async {
    store['jwt_token'] = 'stored-jwt';
    final container = buildContainer(
      MockClient((request) async => http.Response(jsonEncode({'message': 'Bad request'}), 400)),
    );

    await expectLater(
      container.read(songsRepositoryProvider).generate(text: 'notes', genre: 'Lo-Fi', mood: 'Calm Study Vibe'),
      throwsA(isA<ApiException>()),
    );
  });

  test('throws StateError when called while signed out', () async {
    final container = buildContainer(MockClient((request) async => http.Response('', 500)));

    await expectLater(
      container.read(songsRepositoryProvider).generate(text: 'notes', genre: 'Lo-Fi', mood: 'Calm Study Vibe'),
      throwsA(isA<StateError>()),
    );
  });
}
