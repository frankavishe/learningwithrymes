import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/audio_player_providers.dart';
import 'core/auth/auth_session_providers.dart';
import 'core/storage/local_cache_service.dart';

class RhythmNotesApp extends StatelessWidget {
  const RhythmNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RhythmNotes',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const AppShellHome(),
    );
  }
}

/// Placeholder landing screen for the app shell. Phase 8 replaces this with
/// real auth-gated routing (sign in -> Screens 2-4); for now it exists to
/// prove the Phase 7 dependencies (Riverpod, just_audio, path_provider,
/// flutter_secure_storage) are wired end-to-end.
class AppShellHome extends ConsumerWidget {
  const AppShellHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenState = ref.watch(authTokenProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('RhythmNotes')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note, size: 64),
              const SizedBox(height: 16),
              const Text(
                'App shell ready — Screens 1-4 land in Phases 8-11.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              tokenState.when(
                data: (token) => Text(
                  token == null ? 'Signed out (no stored JWT)' : 'Signed in',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                loading: () => const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (error, _) => Text('Session check failed: $error'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _runDiagnostics(context, ref),
                child: const Text('Run dependency smoke test'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runDiagnostics(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final results = <String>[];

    try {
      final storage = ref.read(secureStorageServiceProvider);
      await storage.writeToken('diagnostic-token');
      final readBack = await storage.readToken();
      await storage.deleteToken();
      results.add(readBack == 'diagnostic-token' ? 'secure_storage: OK' : 'secure_storage: MISMATCH');
    } catch (e) {
      results.add('secure_storage: FAILED ($e)');
    }

    try {
      final cache = LocalCacheService();
      final dir = await cache.songCacheDirectory();
      results.add(await dir.exists() ? 'path_provider: OK (${dir.path})' : 'path_provider: MISSING DIR');
    } catch (e) {
      results.add('path_provider: FAILED ($e)');
    }

    try {
      final player = ref.read(audioPlayerProvider);
      results.add('just_audio: OK (state=${player.processingState.name})');
    } catch (e) {
      results.add('just_audio: FAILED ($e)');
    }

    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(results.join(' | '))));
  }
}
