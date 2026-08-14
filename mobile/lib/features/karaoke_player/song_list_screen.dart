import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/songs/songs_repository.dart';
import 'karaoke_player_screen.dart';

/// Minimal flat song list (`GET /api/songs`, `API-001`) — exists only to give
/// Phase 10's [KaraokePlayerScreen] a real, tappable entry point in the app
/// shell. Deliberately NOT grouped by subject and has no offline-cache
/// toggle: that's Phase 11's job (`specs/11-screen-library.md`,
/// `UI-LIBRARY-001`/`002`), which will very likely replace this screen
/// outright rather than build on it.
class SongListScreen extends ConsumerStatefulWidget {
  const SongListScreen({super.key});

  @override
  ConsumerState<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends ConsumerState<SongListScreen> {
  late Future<List<Song>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = ref.read(songsRepositoryProvider).listSongs();
  }

  Future<void> _refresh() {
    final future = ref.read(songsRepositoryProvider).listSongs();
    setState(() => _songsFuture = future);
    // RefreshIndicator awaits this to know when to hide its spinner; errors
    // still surface via the FutureBuilder's snapshot below.
    return future.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<Song>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Could not load your songs. Please try again.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final songs = snapshot.data!;
          if (songs.isEmpty) {
            return const Center(child: Text('No songs yet — generate one from the New song tab.'));
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(song.title),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => KaraokePlayerScreen(songId: song.id)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
