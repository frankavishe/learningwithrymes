import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmnotes_app/core/songs/lyric_parser.dart';

/// Unit tests for [parseLyrics] — the client-side timestamp estimation that
/// resolves `specs/10-screen-karaoke-player.md`'s open question (no
/// forced-alignment metadata comes back from the audio-gen provider).
void main() {
  const lyrics = '''
[Verse 1]
Newton's first law, an object at rest
[Chorus]
Stays at rest, stays at rest
Unless a force acts, unless a force acts
[Verse 2]
F equals m times a, that's the key
[Outro]
Physics sets us free
Forces align with thee
''';

  group('parseLyrics', () {
    test('splits lines evenly across the total duration, in reading order', () {
      final parsed = parseLyrics(lyrics, const Duration(seconds: 60));

      expect(parsed.lines, hasLength(6));
      expect(parsed.lines[0].section, 'Verse 1');
      expect(parsed.lines[0].text, "Newton's first law, an object at rest");
      expect(parsed.lines[0].start, Duration.zero);
      expect(parsed.lines[1].section, 'Chorus');
      expect(parsed.lines[1].text, 'Stays at rest, stays at rest');
      // 60s / 6 lines = 10s per line.
      expect(parsed.lines[1].start, const Duration(seconds: 10));
      expect(parsed.lines.last.end, const Duration(seconds: 60));
    });

    test('ignores blank lines and lines before the first section marker', () {
      final parsed = parseLyrics('\n\n$lyrics\n\n', const Duration(seconds: 60));
      expect(parsed.lines, hasLength(6));
    });

    test('returns no lines for lyrics with no content', () {
      expect(parseLyrics('', const Duration(seconds: 60)).lines, isEmpty);
      expect(parseLyrics('[Verse 1]\n[Chorus]', const Duration(seconds: 60)).lines, isEmpty);
    });

    test('returns no lines when the total duration is zero', () {
      expect(parseLyrics(lyrics, Duration.zero).lines, isEmpty);
    });

    test('chorusRange spans the first to last chorus line', () {
      final parsed = parseLyrics(lyrics, const Duration(seconds: 60));
      final range = parsed.chorusRange!;
      expect(range.start, const Duration(seconds: 10));
      expect(range.end, const Duration(seconds: 30));
    });

    test('chorusRange is null when there is no chorus section', () {
      final parsed = parseLyrics('[Verse 1]\nJust a verse', const Duration(seconds: 60));
      expect(parsed.chorusRange, isNull);
    });
  });

  group('ParsedLyrics.indexAt', () {
    late final parsed = parseLyrics(lyrics, const Duration(seconds: 60));

    test('finds the active line for a mid-song position', () {
      expect(parsed.indexAt(const Duration(seconds: 15)), 1);
      expect(parsed.indexAt(const Duration(seconds: 45)), 4);
    });

    test('returns the last index once playback reaches the end', () {
      expect(parsed.indexAt(const Duration(seconds: 60)), 5);
    });

    test('returns -1 for an empty ParsedLyrics', () {
      expect(const ParsedLyrics([]).indexAt(Duration.zero), -1);
    });
  });
}
