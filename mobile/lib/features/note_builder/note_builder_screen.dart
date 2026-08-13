import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/songs/songs_repository.dart';

/// Screen 2 (`specs/09-screen-note-builder.md`): submits study notes plus
/// genre/mood/subject to `POST /api/songs/generate` (`API-006`). Content-only
/// — no `Scaffold`/`AppBar` of its own — so `app.dart`'s `AuthenticatedShell`
/// can own that chrome (and later swap in Screens 3-4 from Phases 10-11
/// alongside it).
class NoteBuilderScreen extends ConsumerStatefulWidget {
  const NoteBuilderScreen({super.key});

  @override
  ConsumerState<NoteBuilderScreen> createState() => _NoteBuilderScreenState();
}

class _NoteBuilderScreenState extends ConsumerState<NoteBuilderScreen> {
  // UI-BUILDER-002: matches the example genres from the spec verbatim.
  static const _genres = ['Afrobeat', 'Synthwave', 'Lo-Fi', 'Hip-Hop', 'Classical'];

  // UI-BUILDER-003: matches the example mood chips from the spec verbatim.
  static const _moodPresets = ['Feeling of Strength', 'Upbeat / Ripe Banana', 'Calm Study Vibe'];

  final _textController = TextEditingController();
  final _customMoodController = TextEditingController();
  final _subjectController = TextEditingController();

  String? _selectedGenre;
  String? _selectedMoodChip;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _textController.dispose();
    _customMoodController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  /// A custom feeling prompt wins over a preset chip when both are present
  /// (UI-BUILDER-003) — selecting a chip clears the custom field and vice
  /// versa, so in practice only one is ever set at a time.
  String? get _effectiveMood {
    final custom = _customMoodController.text.trim();
    return custom.isNotEmpty ? custom : _selectedMoodChip;
  }

  // A genre and a mood must both be selected before submission is enabled
  // (UI-BUILDER-002/003's acceptance criterion); non-empty notes are
  // required by the API DTO regardless (GenerateSongDto.text).
  bool get _canSubmit =>
      !_isSubmitting && _textController.text.trim().isNotEmpty && _selectedGenre != null && _effectiveMood != null;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New song', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text('Study notes', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              // UI-BUILDER-001
              controller: _textController,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: 'Paste or type your notes, formulas, or anything you want turned into lyrics…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Text('Genre', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SizedBox(
              // UI-BUILDER-002: horizontal chip selector.
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _genres.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final genre = _genres[index];
                  return ChoiceChip(
                    label: Text(genre),
                    selected: _selectedGenre == genre,
                    onSelected: (selected) => setState(() => _selectedGenre = selected ? genre : null),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text('Mood', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              // UI-BUILDER-003: preset chips...
              spacing: 8,
              runSpacing: 8,
              children: _moodPresets.map((mood) {
                return ChoiceChip(
                  label: Text(mood),
                  selected: _selectedMoodChip == mood,
                  onSelected: (selected) => setState(() {
                    _selectedMoodChip = selected ? mood : null;
                    if (selected) _customMoodController.clear();
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            TextField(
              // ...plus a custom feeling prompt.
              controller: _customMoodController,
              decoration: const InputDecoration(
                labelText: 'Or describe your own feeling',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                if (value.trim().isNotEmpty) _selectedMoodChip = null;
              }),
            ),
            const SizedBox(height: 20),
            Text('Subject', style: Theme.of(context).textTheme.labelLarge), // UI-BUILDER-004
            const SizedBox(height: 8),
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(
                hintText: 'e.g. Organic Chemistry',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Generate song'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    final genre = _selectedGenre;
    final mood = _effectiveMood;
    if (genre == null || mood == null) {
      // Guarded by _canSubmit, but keeps this method sound under the
      // null-safe reads below regardless.
      setState(() => _isSubmitting = false);
      return;
    }

    final repository = ref.read(songsRepositoryProvider);
    try {
      await repository.generate(
        text: _textController.text.trim(),
        genre: genre,
        mood: mood,
        subject: _subjectController.text.trim().isEmpty ? null : _subjectController.text.trim(),
      );
      if (!mounted) return;
      // UI-BUILDER-005 / AI-005: confirms the job was enqueued, not that the
      // song is ready — generation itself runs async.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Song generation started — check your library soon.')),
      );
      _textController.clear();
      _customMoodController.clear();
      _subjectController.clear();
      setState(() {
        _selectedGenre = null;
        _selectedMoodChip = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
