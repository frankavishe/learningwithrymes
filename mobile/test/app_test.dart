import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rhythmnotes_app/app.dart';
import 'package:rhythmnotes_app/core/network/api_client.dart';

/// End-to-end smoke tests for the app shell's auth-gated root (`app.dart`,
/// `UI-AUTH-001`/`UI-AUTH-002`): signed-out users land on [AuthScreen],
/// signed-in users (JWT already in secure storage) land on
/// [AuthenticatedShell] with Phase 9's note builder and Phase 10's song list
/// tabs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  setUp(() {
    store.clear();
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

  // AuthenticatedShell mounts SongListScreen (Phase 10) alongside the note
  // builder via IndexedStack, so it fires GET /api/songs immediately — stub
  // it rather than hitting the real (unreachable in tests) backend.
  Widget buildApp() => ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://test.local/api',
              client: MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
        ],
        child: const RhythmNotesApp(),
      );

  testWidgets('shows the sign-in form when signed out', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });

  testWidgets('shows the authenticated shell (note builder) when a JWT is already stored', (tester) async {
    store['jwt_token'] = 'seeded-token';

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'RhythmNotes'), findsOneWidget);
    expect(find.text('New song'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Generate song'), findsOneWidget);
    expect(find.text('Write'), findsOneWidget);
    expect(find.text('Songs'), findsOneWidget);
  });

  testWidgets('the Songs tab shows the song list', (tester) async {
    store['jwt_token'] = 'seeded-token';

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Songs'));
    await tester.pumpAndSettle();

    expect(find.text('No songs yet — generate one from the New song tab.'), findsOneWidget);
  });

  testWidgets('signing out returns to the sign-in form', (tester) async {
    store['jwt_token'] = 'seeded-token';

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.text('New song'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
    expect(store.containsKey('jwt_token'), isFalse);
  });
}
