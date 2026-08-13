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
import 'package:rhythmnotes_app/features/note_builder/note_builder_screen.dart';

/// Widget tests for [NoteBuilderScreen] (`specs/09-screen-note-builder.md`):
/// the submit gate (genre + mood required, `UI-BUILDER-002`/`003`), the
/// custom-mood/preset-chip interplay, and — per the acceptance criteria —
/// that submitting calls `POST /api/songs/generate` and surfaces feedback
/// that a job started (`UI-BUILDER-005`), with a failed request showing an
/// inline error instead of crashing the screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{'jwt_token': 'stored-jwt'};

  setUp(() {
    store
      ..clear()
      ..['jwt_token'] = 'stored-jwt';
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

  Future<void> pumpScreen(WidgetTester tester, http.Client mockHttpClient) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://test.local/api', client: mockHttpClient)),
          secureStorageServiceProvider
              .overrideWithValue(SecureStorageService(storage: const FlutterSecureStorage())),
        ],
        child: const MaterialApp(home: Scaffold(body: NoteBuilderScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('submit is disabled until notes, a genre, and a mood are all set', (tester) async {
    await pumpScreen(tester, MockClient((request) async => http.Response('', 500)));

    FilledButton submitButton() => tester.widget(find.widgetWithText(FilledButton, 'Generate song'));
    expect(submitButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'E = mc^2');
    await tester.pump();
    expect(submitButton().onPressed, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Synthwave'));
    await tester.pump();
    expect(submitButton().onPressed, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Calm Study Vibe'));
    await tester.pump();
    expect(submitButton().onPressed, isNotNull);
  });

  testWidgets('a custom mood clears the selected preset chip', (tester) async {
    await pumpScreen(tester, MockClient((request) async => http.Response('', 500)));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Calm Study Vibe'));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Calm Study Vibe')).selected, isTrue);

    await tester.enterText(find.widgetWithText(TextField, 'Or describe your own feeling'), 'Feeling of Strength');
    await tester.pump();

    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Calm Study Vibe')).selected, isFalse);
  });

  testWidgets('submitting calls the generate endpoint and confirms the job started', (tester) async {
    late Map<String, dynamic> capturedBody;
    String? capturedAuthHeader;
    await pumpScreen(
      tester,
      MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'promptId': 'prompt-1', 'jobId': 'job-1'}), 202);
      }),
    );

    await tester.enterText(find.byType(TextField).first, 'E = mc^2');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Synthwave'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Calm Study Vibe'));
    await tester.enterText(find.widgetWithText(TextField, 'e.g. Organic Chemistry'), 'Physics');
    await tester.pump();

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Generate song'));
    await tester.tap(find.widgetWithText(FilledButton, 'Generate song'));
    await tester.pumpAndSettle();

    expect(capturedAuthHeader, 'Bearer stored-jwt');
    expect(capturedBody, {
      'text': 'E = mc^2',
      'genre': 'Synthwave',
      'mood': 'Calm Study Vibe',
      'subject': 'Physics',
    });
    expect(find.text('Song generation started — check your library soon.'), findsOneWidget);
  });

  testWidgets('a failed request shows an inline error, not a crash', (tester) async {
    await pumpScreen(
      tester,
      MockClient((request) async {
        return http.Response(jsonEncode({'statusCode': 500, 'message': 'Something broke'}), 500);
      }),
    );

    await tester.enterText(find.byType(TextField).first, 'E = mc^2');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Synthwave'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Calm Study Vibe'));
    await tester.pump();

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Generate song'));
    await tester.tap(find.widgetWithText(FilledButton, 'Generate song'));
    await tester.pumpAndSettle();

    expect(find.text('Something broke'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
