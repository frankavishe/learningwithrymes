import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmnotes_app/app.dart';

/// End-to-end smoke test for the Phase 7 app shell: boots [RhythmNotesApp]
/// under a real [ProviderScope] (`MOBILE-002`) and runs the in-app
/// diagnostics button, which exercises flutter_secure_storage,
/// path_provider, and just_audio (`MOBILE-003`..`MOBILE-005`) together.
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

  testWidgets('app shell boots signed-out under ProviderScope', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RhythmNotesApp()));
    await tester.pumpAndSettle();

    expect(find.text('App shell ready — Screens 1-4 land in Phases 8-11.'), findsOneWidget);
    expect(find.text('Signed out (no stored JWT)'), findsOneWidget);
  });

  testWidgets('dependency smoke test button reports all three plugins OK', (tester) async {
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

    final snackBarTextFinder = find.textContaining('secure_storage:');
    expect(snackBarTextFinder, findsOneWidget);
    final snackBarText = tester.widget<Text>(snackBarTextFinder);
    expect(snackBarText.data, contains('secure_storage: OK'));
    expect(snackBarText.data, contains('path_provider: OK'));
    expect(snackBarText.data, contains('just_audio: OK'));
  });
}
