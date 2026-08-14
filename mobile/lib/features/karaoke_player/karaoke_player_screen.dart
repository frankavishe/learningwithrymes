import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_player_providers.dart';
import '../../core/audio/karaoke_audio_player.dart';
import '../../core/network/api_client.dart';
import '../../core/songs/lyric_parser.dart';
import '../../core/songs/songs_repository.dart';

enum _Stem { full, vocals, beat }

/// Screen 3 (`specs/10-screen-karaoke-player.md`): plays a completed song
/// (`GET /api/songs/:id`, `API-002`) with synced auto-scrolling lyrics
/// (`UI-PLAYER-001`), play/pause/seek/loop-chorus controls (`UI-PLAYER-002`),
/// and vocal/beat stem toggles (`UI-PLAYER-003`). Pushed as its own route
/// (owns its `Scaffold`/`AppBar`) rather than living in `AuthenticatedShell`'s
/// body, since it needs a specific song to play.
class KaraokePlayerScreen extends ConsumerStatefulWidget {
  const KaraokePlayerScreen({super.key, required this.songId});

  final String songId;

  @override
  ConsumerState<KaraokePlayerScreen> createState() => _KaraokePlayerScreenState();
}

class _KaraokePlayerScreenState extends ConsumerState<KaraokePlayerScreen> {
  static const _lineHeight = 56.0;

  final _scrollController = ScrollController();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;

  Song? _song;
  ParsedLyrics? _lyrics;
  Duration _totalDuration = Duration.zero;
  String? _loadError;

  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _loopChorus = false;
  _Stem _stem = _Stem.full;
  int _highlightedIndex = -1;

  KaraokeAudioPlayer get _player => ref.read(karaokeAudioPlayerProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _retry() {
    setState(() => _loadError = null);
    return _load();
  }

  Future<void> _load() async {
    try {
      final song = await ref.read(songsRepositoryProvider).getSong(widget.songId);
      final total = Duration(seconds: song.durationSeconds ?? 60);
      await _player.setUrl(song.audioFileUrl);
      // just_audio (Android/ExoPlayer) can start playback as soon as a
      // source is loaded rather than waiting for an explicit play() call —
      // force a known paused state so the screen always opens paused
      // regardless of that default.
      await _player.pause();
      _positionSub = _player.positionStream.listen(_onPosition);
      _playingSub = _player.playingStream.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });
      if (!mounted) return;
      setState(() {
        _song = song;
        _totalDuration = total;
        _lyrics = parseLyrics(song.generatedLyrics, total);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Could not load this song. Please try again.');
    }
  }

  void _onPosition(Duration position) {
    if (!mounted) return;
    setState(() {
      _position = position;
      final index = _lyrics?.indexAt(position) ?? -1;
      if (index != _highlightedIndex) {
        _highlightedIndex = index;
        _scrollToIndex(index);
      }
    });
    _maybeLoopChorus(position);
  }

  void _maybeLoopChorus(Duration position) {
    if (!_loopChorus) return;
    final range = _lyrics?.chorusRange;
    if (range == null) return;
    if (position >= range.end) _player.seek(range.start);
  }

  void _scrollToIndex(int index) {
    if (index < 0 || !_scrollController.hasClients) return;
    // Keeps the active line roughly a third of the way down the viewport
    // rather than pinned to the very top.
    final viewport = _scrollController.position.viewportDimension;
    final target = (index * _lineHeight) - viewport / 3;
    _scrollController.animateTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _togglePlayback() => _isPlaying ? _player.pause() : _player.play();

  Future<void> _switchStem(_Stem selection) async {
    final song = _song;
    if (song == null || selection == _stem) return;
    final url = switch (selection) {
      _Stem.full => song.audioFileUrl,
      _Stem.vocals => song.vocalStemUrl,
      _Stem.beat => song.beatStemUrl,
    };
    if (url == null) return; // Stem not available for this song — toggle stays disabled.

    final resumePosition = _position;
    final wasPlaying = _isPlaying;
    if (wasPlaying) await _player.pause();
    await _player.setUrl(url, position: resumePosition); // UI-PLAYER-003: position preserved.
    if (wasPlaying) await _player.play();
    if (mounted) setState(() => _stem = selection);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _playingSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_song?.title ?? 'Loading…')),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final error = _loadError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _retry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final song = _song;
    final lyrics = _lyrics;
    if (song == null || lyrics == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(child: _buildLyrics(lyrics)),
        _buildStemToggles(song),
        _buildControls(lyrics),
      ],
    );
  }

  Widget _buildLyrics(ParsedLyrics lyrics) {
    if (lyrics.lines.isEmpty) {
      return const Center(child: Text('No lyrics to display for this song.'));
    }
    return ListView.builder(
      // UI-PLAYER-001: fixed extent keeps scroll-offset math in
      // `_scrollToIndex` a simple `index * _lineHeight` — no per-line
      // measurement needed.
      controller: _scrollController,
      itemExtent: _lineHeight,
      itemCount: lyrics.lines.length,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      itemBuilder: (context, index) {
        final line = lyrics.lines[index];
        final isActive = index == _highlightedIndex;
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            line.text,
            style: TextStyle(
              fontSize: isActive ? 20 : 16,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }

  Widget _buildStemToggles(Song song) {
    // UI-PLAYER-003: MusicGen (specs/04-ai-generation-pipeline.md) doesn't
    // produce stems yet, so vocalStemUrl/beatStemUrl are null on every song
    // generated so far — the toggles stay disabled (not hidden) until a
    // future pipeline change starts populating them.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Full mix'),
            selected: _stem == _Stem.full,
            onSelected: (_) => _switchStem(_Stem.full),
          ),
          ChoiceChip(
            label: const Text('Vocals'),
            selected: _stem == _Stem.vocals,
            onSelected: song.vocalStemUrl == null ? null : (_) => _switchStem(_Stem.vocals),
          ),
          ChoiceChip(
            label: const Text('Beat'),
            selected: _stem == _Stem.beat,
            onSelected: song.beatStemUrl == null ? null : (_) => _switchStem(_Stem.beat),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ParsedLyrics lyrics) {
    final totalMs = _totalDuration.inMilliseconds.toDouble();
    final positionMs = _position.inMilliseconds.toDouble().clamp(0.0, totalMs == 0 ? 1.0 : totalMs);
    final hasChorus = lyrics.chorusRange != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Slider(
            value: totalMs == 0 ? 0 : positionMs,
            max: totalMs == 0 ? 1 : totalMs,
            onChanged: totalMs == 0 ? null : (value) => _player.seek(Duration(milliseconds: value.round())),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_formatDuration(_position)),
              const SizedBox(width: 24),
              IconButton(
                iconSize: 40,
                icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                onPressed: _togglePlayback,
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.repeat),
                tooltip: 'Loop chorus',
                color: _loopChorus ? Theme.of(context).colorScheme.primary : null,
                onPressed: hasChorus ? () => setState(() => _loopChorus = !_loopChorus) : null,
              ),
              const SizedBox(width: 24),
              Text(_formatDuration(_totalDuration)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
