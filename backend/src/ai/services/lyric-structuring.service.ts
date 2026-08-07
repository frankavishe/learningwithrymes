import { BadGatewayException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GoogleGenAI, Type } from '@google/genai';
import { LYRIC_SECTION_MARKERS } from '../ai.constants';
import { GenerateSongJobData, StructuredLyrics } from '../types/pipeline.types';

const MAX_ATTEMPTS = 2;

// Stage 1 of the pipeline (specs/04-ai-generation-pipeline.md) — turns raw academic notes into
// structured, singable lyrics via Gemini. Satisfies AI-001, AI-002, AI-003.
@Injectable()
export class LyricStructuringService {
  private readonly logger = new Logger(LyricStructuringService.name);
  private readonly client: GoogleGenAI;
  private readonly model: string;

  constructor(private readonly config: ConfigService) {
    this.client = new GoogleGenAI({
      apiKey: this.config.get<string>('GEMINI_API_KEY'),
    });
    this.model = this.config.get<string>('GEMINI_MODEL', 'gemini-2.5-flash');
  }

  async structure(
    input: Pick<
      GenerateSongJobData,
      'rawText' | 'genre' | 'mood' | 'targetSubject'
    >,
  ): Promise<StructuredLyrics> {
    let lastInvalidLyrics = '';

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const result = await this.requestStructuredLyrics(
        input,
        lastInvalidLyrics,
      );
      if (this.hasValidSectionMarkers(result.lyrics)) {
        return result;
      }
      this.logger.warn(
        `Stage 1 output missing/misordered section markers on attempt ${attempt}; retrying`,
      );
      lastInvalidLyrics = result.lyrics;
    }

    throw new BadGatewayException(
      'Lyric structuring did not produce the required [Verse 1]/[Chorus]/[Verse 2]/[Outro] sections',
    );
  }

  private async requestStructuredLyrics(
    input: Pick<
      GenerateSongJobData,
      'rawText' | 'genre' | 'mood' | 'targetSubject'
    >,
    previousInvalidAttempt: string,
  ): Promise<StructuredLyrics> {
    const response = await this.client.models.generateContent({
      model: this.model,
      contents: this.buildPrompt(input, previousInvalidAttempt),
      config: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            title: { type: Type.STRING },
            lyrics: { type: Type.STRING },
          },
          required: ['title', 'lyrics'],
        },
      },
    });

    const text = response.text;
    if (!text) {
      throw new BadGatewayException(
        'Lyric structuring returned an empty response',
      );
    }

    const parsed = JSON.parse(text) as StructuredLyrics;
    return { title: parsed.title, lyrics: parsed.lyrics };
  }

  private buildPrompt(
    input: Pick<
      GenerateSongJobData,
      'rawText' | 'genre' | 'mood' | 'targetSubject'
    >,
    previousInvalidAttempt: string,
  ): string {
    const sections = LYRIC_SECTION_MARKERS.join(', ');
    const retryNote = previousInvalidAttempt
      ? `\nYour previous attempt did not use exactly these four section markers in order:\n"""${previousInvalidAttempt}"""\nFix that.`
      : '';

    return `You are turning a student's raw study notes into song lyrics for an educational karaoke app.

Genre: ${input.genre}
Mood: ${input.mood}
${input.targetSubject ? `Subject: ${input.targetSubject}` : ''}

Raw notes:
"""
${input.rawText}
"""

Rules:
1. Preserve every key academic term, formula, and definition from the raw notes VERBATIM — do not
   paraphrase, simplify, or drop them. (AI-001)
2. Format the lyrics into exactly these four sections, in this exact order, each on its own line as a
   literal marker: ${sections}. No other section markers, no extra commentary. (AI-002)
3. Write the lines to fit a rhythmic meter that matches the "${input.genre}" genre and "${input.mood}"
   mood. (AI-003)
4. Also produce a short, catchy song title (not one of the section markers).
${retryNote}

Respond with JSON matching the given schema.`;
  }

  // AI-002 acceptance criterion: exactly the four markers, in order, nothing else.
  private hasValidSectionMarkers(lyrics: string): boolean {
    if (!lyrics) return false;
    const found = lyrics
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => /^\[.+\]$/.test(line));

    if (found.length !== LYRIC_SECTION_MARKERS.length) return false;
    return found.every((marker, i) => marker === LYRIC_SECTION_MARKERS[i]);
  }
}
