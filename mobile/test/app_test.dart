import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmnotes_app/app.dart';

/// End-to-end smoke tests for the app shell's auth-gated root (`app.dart`,
/// `UI-AUTH-001`/`UI-AUTH-002`): signed-out users land on [AuthScreen],
/// signed-in users (JWT already in secure storage) land on
/// [AuthenticatedShell], and its diagnostics button still exercises
/// path_provider and just_audio (`MOBILE-003`/`MOBILE-004`) end to end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final store = <String, String>{};
  late Directory fakeDocsDir;

  setUp(() async {
    store.clear();
    fakeDocsDir = await Directory.systemTemp.createTemp('rhythmnotes_test_docs_');

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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return fakeDocsDir.path;
      throw MissingPluginException();
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await fakeDocsDir.exists()) {
      await fakeDocsDir.delete(recursive: true);
    }
  });

  testWidgets('shows the sign-in form when signed out', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RhythmNotesApp()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });

  testWidgets('shows the authenticated shell when a JWT is already stored', (tester) async {
    store['jwt_token'] = 'seeded-token';

    await tester.pumpWidget(const ProviderScope(child: RhythmNotesApp()));
    await tester.pumpAndSettle();

    expect(find.text('Signed in — Screens 2-4 land in Phases 9-11.'), findsOneWidget);
  });

  testWidgets('signing out returns to the sign-in form', (tester) async {
    store['jwt_token'] = 'seeded-token';

    await tester.pumpWidget(const ProviderScope(child: RhythmNotesApp()));
    await tester.pumpAndSettle();
    expect(find.text('Signed in — Screens 2-4 land in Phases 9-11.'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
    expect(store.containsKey('jwt_token'), isFalse);
  });

  testWidgets('dependency smoke test button reports path_provider and just_audio OK', (tester) async {
    store['jwt_token'] = 'seeded-token';

    await tester.pumpWidget(const ProviderScope(child: RhythmNotesApp()));
    await tester.pumpAndSettle();

    // The diagnostics handler does real dart:io work (LocalCacheService),
    // which the fake-async zone testWidgets() runs in won't drive to
    // completion on its own — runAsync() escapes to the real event loop for
    // that part. pump() (not pumpAndSettle()) afterward avoids racing the
    // SnackBar's auto-dismiss timer.
    await tester.runAsync(() async {
      await tester.tap(find.text('Run dependency smoke test'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(); // rebuild with results and show the SnackBar

    final snackBarTextFinder = find.textContaining('path_provider:');
    expect(snackBarTextFinder, findsOneWidget);
    final snackBarText = tester.widget<Text>(snackBarTextFinder);
    expect(snackBarText.data, contains('path_provider: OK'));
    expect(snackBarText.data, contains('just_audio: OK'));
  });
}
