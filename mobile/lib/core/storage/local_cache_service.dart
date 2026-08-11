import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves the on-device directory used for offline song caching
/// (`MOBILE-004`). Phase 11's library screen downloads a song's audio into
/// this directory for offline playback; this service only owns path
/// resolution, not the download itself.
class LocalCacheService {
  static const _cacheSubdir = 'song_cache';

  Future<Directory> songCacheDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${docsDir.path}${Platform.pathSeparator}$_cacheSubdir');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Path a song's audio would be cached at, keyed by its `songId`.
  /// Extension is fixed to `.mp3` — matches the object key convention
  /// `songs/<uuid>.mp3` from `StorageService.uploadFromUrl` (Phase 6).
  Future<File> cachedFileFor(String songId) async {
    final cacheDir = await songCacheDirectory();
    return File('${cacheDir.path}${Platform.pathSeparator}$songId.mp3');
  }

  Future<bool> isCached(String songId) async {
    final file = await cachedFileFor(songId);
    return file.exists();
  }
}
