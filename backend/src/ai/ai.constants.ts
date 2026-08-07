// Shared constants for the AI generation pipeline (specs/04-ai-generation-pipeline.md).

// BullMQ queue name backing AI-005's async job execution.
export const SONG_GENERATION_QUEUE = 'song-generation';

// AI-002 — Stage 1 output must contain exactly these four section markers, in this order.
export const LYRIC_SECTION_MARKERS = [
  '[Verse 1]',
  '[Chorus]',
  '[Verse 2]',
  '[Outro]',
] as const;

// Stage 2 (Replicate/MusicGen) generates an instrumental backing track — see the "Instrumental-only
// audio-gen" resolution in specs/04-ai-generation-pipeline.md Open Questions. This is the clip length
// requested per generation; there's no per-song override yet.
export const DEFAULT_AUDIO_DURATION_SECONDS = 60;

// Always included in Stage 2's `tags` payload (AI-004), matching the spec's reference example.
export const EDUCATIONAL_TAG = 'Educational';
