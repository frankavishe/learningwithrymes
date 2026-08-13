import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmnotes_app/app.dart';

/// End-to-end smoke tests for the app shell's auth-gated root (`app.dart`,
/// `UI-AUTH-001`/`UI-AUTH-002`): signed-out users land on [AuthScreen],
/// signed-in users (JWT already in secure storage) land on
/// [AuthenticatedShell] with Phase 9's note builder as its body.
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

  testWidgets('shows the sign-in form when signed out', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RhythmNotesApp()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });

  testWidgets('shows the authenticated shell (note builder) when a JWT is already stored', (tester) async {
    store['jwt_token'] = 'seeded-token';

    await tester.pumpWidget(const ProviderScope(child: RhythmNotesApp()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'RhythmNotes'), findsOneWidget);
    expect(find.text('New song'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Generate song'), findsOneWidget);
  });

  testWidgets('signing out returns to the sign-in form', (tester) async {
    store['jwt_token'] = 'seeded-token';

    await tester.pumpWidget(const ProviderScope(child: RhythmNotesApp()));
    await tester.pumpAndSettle();
    expect(find.text('New song'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
    expect(store.containsKey('jwt_token'), isFalse);
  });
}
