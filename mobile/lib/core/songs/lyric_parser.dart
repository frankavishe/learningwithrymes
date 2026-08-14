/// Parses `Song.generatedLyrics` (AI-002's `[Verse 1]`/`[Chorus]`/`[Verse 2]`/
/// `[Outro]`-marked text) into timed lines for the karaoke player
/// (`specs/10-screen-karaoke-player.md`, `UI-PLAYER-001`).
library;

final _sectionMarkerPattern = RegExp(r'^\[(.+)\]$');

/// One lyric line with its estimated on-screen window and the section
/// (`Verse 1`, `Chorus`, ...) it belongs to.
class LyricLine {
  const LyricLine({
    required this.section,
    required this.text,
    required this.start,
    required this.end,
  });

  final String section;
  final String text;
  final Duration start;
  final Duration end;

  bool containsPosition(Duration position) => position >= start && position < end;
}

/// Timed lyrics for a song, plus the chorus lookup the loop-chorus control
/// needs (`UI-PLAYER-002`).
class ParsedLyrics {
  const ParsedLyrics(this.lines);

  final List<LyricLine> lines;

  /// Index of the line active at [position]; `-1` if [lines] is empty or
  /// [position] falls after the last line (trailing instrumental).
  int indexAt(Duration position) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].containsPosition(position)) return i;
    }
    if (lines.isNotEmpty && position >= lines.last.end) return lines.length - 1;
    return -1;
  }

  /// Start/end window spanning every `[Chorus]` line, for the loop-chorus
  /// control — `null` when the lyrics have no chorus section at all (a
  /// malformed generation, since AI-002 requires one).
  ///
  /// Named record fields (`{Duration start, ...}`) so callers get `.start`/
  /// `.end` accessors — plain positional record "names" like
  /// `(Duration start, Duration end)` are documentation-only in Dart and
  /// don't produce real accessors.
  ({Duration start, Duration end})? get chorusRange {
    final chorusLines = lines.where((line) => line.section.toLowerCase().contains('chorus'));
    if (chorusLines.isEmpty) return null;
    return (start: chorusLines.first.start, end: chorusLines.last.end);
  }
}

/// Estimates per-line playback windows client-side.
///
/// **Resolves the open question in `specs/10-screen-karaoke-player.md`**:
/// Stage 2's audio-gen provider (MusicGen, `specs/04-ai-generation-pipeline.md`)
/// is instrumental-only and returns no forced-alignment/timing metadata, so
/// there's nothing server-side to consume. This divides [totalDuration] evenly
/// across every non-marker lyric line in reading order — good enough for
/// karaoke-along highlighting without a real alignment pipeline. A future
/// phase could replace this with provider-supplied per-line timestamps
/// without changing [ParsedLyrics]'s shape.
ParsedLyrics parseLyrics(String rawLyrics, Duration totalDuration) {
  final entries = <({String section, String text})>[];
  var currentSection = 'Intro';

  for (final rawLine in rawLyrics.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final marker = _sectionMarkerPattern.firstMatch(line);
    if (marker != null) {
      currentSection = marker.group(1)!;
      continue;
    }
    entries.add((section: currentSection, text: line));
  }

  if (entries.isEmpty || totalDuration <= Duration.zero) return const ParsedLyrics([]);

  final slice = totalDuration ~/ entries.length;
  final lines = <LyricLine>[
    for (var i = 0; i < entries.length; i++)
      LyricLine(
        section: entries[i].section,
        text: entries[i].text,
        start: slice * i,
        // The last line runs to the true end so integer-division rounding
        // doesn't strand a few trailing seconds with no active line.
        end: i == entries.length - 1 ? totalDuration : slice * (i + 1),
      ),
  ];
  return ParsedLyrics(lines);
}
