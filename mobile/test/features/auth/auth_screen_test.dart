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
import 'package:rhythmnotes_app/features/auth/auth_screen.dart';

/// Widget tests for [AuthScreen] (`specs/08-screen-auth.md`): client-side
/// validation, the register/login toggle, and — per the acceptance
/// criteria — that a failed request shows an inline error instead of
/// crashing the screen.
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

  Future<void> pumpAuthScreen(WidgetTester tester, http.Client mockHttpClient) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://test.local/api', client: mockHttpClient)),
          secureStorageServiceProvider
              .overrideWithValue(SecureStorageService(storage: const FlutterSecureStorage())),
        ],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('defaults to the login form with no name field', (tester) async {
    await pumpAuthScreen(tester, MockClient((request) async => http.Response('', 500)));

    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });

  testWidgets('toggling to register mode reveals the name field', (tester) async {
    await pumpAuthScreen(tester, MockClient((request) async => http.Response('', 500)));

    await tester.tap(find.text("Don't have an account? Register"));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Create account'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Register'), findsOneWidget);
  });

  testWidgets('submitting an empty form shows validation errors and makes no request', (tester) async {
    var requestCount = 0;
    await pumpAuthScreen(tester, MockClient((request) async {
      requestCount++;
      return http.Response('', 500);
    }));

    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(requestCount, 0);
  });

  testWidgets('invalid credentials show an inline error, not a crash', (tester) async {
    await pumpAuthScreen(
      tester,
      MockClient((request) async {
        return http.Response(
          jsonEncode({'statusCode': 401, 'message': 'Invalid email or password'}),
          401,
        );
      }),
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password'), findsOneWidget);
    // Still on the sign-in screen — no crash, no unhandled exception.
    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a successful login persists the JWT', (tester) async {
    await pumpAuthScreen(
      tester,
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

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(store['jwt_token'], 'jwt.token.here');
    expect(find.text('Invalid email or password'), findsNothing);
  });
}
