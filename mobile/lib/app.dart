import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/audio_player_providers.dart';
import 'core/auth/auth_repository.dart';
import 'core/auth/auth_session_providers.dart';
import 'core/storage/local_cache_service.dart';
import 'features/auth/auth_screen.dart';

class RhythmNotesApp extends StatelessWidget {
  const RhythmNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RhythmNotes',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const _AppRoot(),
    );
  }
}

/// Auth-gated root (`UI-AUTH-001`/`UI-AUTH-002`): shows [AuthScreen] while
/// signed out and [AuthenticatedShell] once a JWT is persisted. Screens 2-4
/// (Phases 9-11) will eventually replace [AuthenticatedShell] with real
/// in-app navigation.
class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenState = ref.watch(authTokenProvider);

    return tokenState.when(
      data: (token) => token == null ? const AuthScreen() : const AuthenticatedShell(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      // An unreadable secure-storage entry shouldn't strand the user on a
      // blank screen — fail safe to the sign-in flow.
      error: (_, _) => const AuthScreen(),
    );
  }
}

/// Placeholder landing screen for signed-in users. Phases 9-11 replace this
/// with Screens 2-4; for now it proves the Phase 7 dependencies (Riverpod,
/// just_audio, path_provider) stay wired end-to-end and offers a sign-out
/// control that exercises `AuthRepository.logout()`.
class AuthenticatedShell extends ConsumerWidget {
  const AuthenticatedShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RhythmNotes'),
        actions: [
          IconButton(
            onPressed: () => ref.read(authRepositoryProvider).logout(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Signed in — Screens 2-4 land in Phases 9-11.',
                textAlign: TextAlign.center,
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

  // Deliberately skips flutter_secure_storage here: MOBILE-005 is now
  // exercised for real by AuthRepository (register/login writes the JWT,
  // logout deletes it), and SecureStorageService is single-purpose around
  // that one `jwt_token` key — a synthetic write/delete here would clobber
  // the live session that got the user onto this screen in the first place.
  Future<void> _runDiagnostics(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final results = <String>[];

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
