import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_repository.dart';
import 'core/auth/auth_session_providers.dart';
import 'features/auth/auth_screen.dart';
import 'features/karaoke_player/song_list_screen.dart';
import 'features/note_builder/note_builder_screen.dart';

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
/// signed out and [AuthenticatedShell] once a JWT is persisted. Screens 3-4
/// (Phases 10-11) will eventually join Phase 9's [NoteBuilderScreen] inside
/// [AuthenticatedShell] via real in-app navigation.
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

/// Shell for signed-in users: owns the top-level `Scaffold`/`AppBar`/bottom
/// nav and the sign-out control (exercising `AuthRepository.logout()`) so
/// content screens — [NoteBuilderScreen] (Phase 9), [SongListScreen] and
/// `KaraokePlayerScreen` (Phase 10) — stay chrome-free and swappable. The
/// bottom nav is a stand-in for real navigation until Phase 11's library
/// screen likely replaces the "Songs" tab.
class AuthenticatedShell extends ConsumerStatefulWidget {
  const AuthenticatedShell({super.key});

  @override
  ConsumerState<AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends ConsumerState<AuthenticatedShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
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
      body: IndexedStack(
        index: _tabIndex,
        children: const [NoteBuilderScreen(), SongListScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.edit_note), label: 'Write'),
          NavigationDestination(icon: Icon(Icons.library_music), label: 'Songs'),
        ],
      ),
    );
  }
}
