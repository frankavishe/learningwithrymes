import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmnotes_app/core/storage/local_cache_service.dart';

/// Verifies [LocalCacheService] wires correctly to path_provider
/// (`MOBILE-004`). Mocks the plugin channel to return a real temp directory
/// so the create/exists calls this service makes are exercised against an
/// actual filesystem, not just a stub path string.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory fakeDocsDir;

  setUp(() async {
    fakeDocsDir = await Directory.systemTemp.createTemp('rhythmnotes_test_docs_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return fakeDocsDir.path;
      }
      throw MissingPluginException();
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await fakeDocsDir.exists()) {
      await fakeDocsDir.delete(recursive: true);
    }
  });

  test('songCacheDirectory creates and returns the cache subdirectory', () async {
    final service = LocalCacheService();

    final dir = await service.songCacheDirectory();

    expect(await dir.exists(), isTrue);
    expect(dir.path, '${fakeDocsDir.path}${Platform.pathSeparator}song_cache');
  });

  test('isCached reflects whether the song file exists on disk', () async {
    final service = LocalCacheService();
    const songId = 'song-123';

    expect(await service.isCached(songId), isFalse);

    final file = await service.cachedFileFor(songId);
    await file.writeAsBytes([1, 2, 3]);

    expect(await service.isCached(songId), isTrue);
  });
}
