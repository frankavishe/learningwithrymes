import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rhythmnotes_app/core/auth/auth_repository.dart';
import 'package:rhythmnotes_app/core/auth/auth_session_providers.dart';
import 'package:rhythmnotes_app/core/network/api_client.dart';
import 'package:rhythmnotes_app/core/storage/secure_storage_service.dart';

/// Verifies [AuthRepository] wires [ApiClient] and [SecureStorageService]
/// together correctly: a successful call persists the JWT (`UI-AUTH-002`)
/// and invalidates [authTokenProvider] so the rest of the app can react.
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

  test('login persists the JWT and invalidates authTokenProvider', () async {
    final container = buildContainer(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'accessToken': 'jwt.token.here',
            'user': {'id': 'user-1', 'name': 'Ada', 'email': 'ada@example.com', 'createdAt': 'now'},
          }),
          200,
        );
      }),
    );

    expect(await container.read(authTokenProvider.future), isNull);

    await container.read(authRepositoryProvider).login(email: 'ada@example.com', password: 'password123');

    expect(store['jwt_token'], 'jwt.token.here');
    expect(await container.read(authTokenProvider.future), 'jwt.token.here');
  });

  test('register persists the JWT the same way as login', () async {
    final container = buildContainer(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'accessToken': 'new-user-jwt',
            'user': {'id': 'user-2', 'name': 'Grace', 'email': 'grace@example.com', 'createdAt': 'now'},
          }),
          201,
        );
      }),
    );

    await container
        .read(authRepositoryProvider)
        .register(name: 'Grace', email: 'grace@example.com', password: 'password123');

    expect(await container.read(authTokenProvider.future), 'new-user-jwt');
  });

  test('a failed login leaves no token behind and rethrows ApiException', () async {
    final container = buildContainer(
      MockClient((request) async {
        return http.Response(jsonEncode({'statusCode': 401, 'message': 'Invalid email or password'}), 401);
      }),
    );

    await expectLater(
      container.read(authRepositoryProvider).login(email: 'ada@example.com', password: 'wrong'),
      throwsA(isA<ApiException>()),
    );
    expect(store.containsKey('jwt_token'), isFalse);
    expect(await container.read(authTokenProvider.future), isNull);
  });

  test('logout deletes the stored token and invalidates authTokenProvider', () async {
    store['jwt_token'] = 'existing-token';
    final container = buildContainer(MockClient((request) async => http.Response('', 500)));

    expect(await container.read(authTokenProvider.future), 'existing-token');

    await container.read(authRepositoryProvider).logout();

    expect(store.containsKey('jwt_token'), isFalse);
    expect(await container.read(authTokenProvider.future), isNull);
  });
}
