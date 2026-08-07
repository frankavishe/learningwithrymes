// Shared types for the AI generation pipeline (specs/04-ai-generation-pipeline.md).

// Input to the whole pipeline — mirrors the `song_prompts` columns (DB-002) so Phase 5's
// `POST /api/songs/generate` handler can enqueue a job straight off the row it just persisted.
export interface GenerateSongJobData {
  promptId: string;
  userId: string;
  rawText: string;
  genre: string;
  mood: string;
  targetSubject: string | null;
}

// Stage 1 (LyricStructuringService) output.
export interface StructuredLyrics {
  title: string;
  // Contains exactly the four LYRIC_SECTION_MARKERS, in order (AI-002).
  lyrics: string;
}

// Stage 2 (AudioGenerationService) request payload — shape mandated by AI-004.
export interface AudioGenerationPayload {
  prompt: string;
  lyrics: string;
  tags: string[];
}

// Stage 2 output, persisted by AI-006.
export interface AudioGenerationResult {
  audioFileUrl: string;
  durationSeconds: number | null;
}
