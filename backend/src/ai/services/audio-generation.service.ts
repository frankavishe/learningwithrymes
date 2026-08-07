import { BadGatewayException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Replicate from 'replicate';
import {
  DEFAULT_AUDIO_DURATION_SECONDS,
  EDUCATIONAL_TAG,
} from '../ai.constants';
import {
  AudioGenerationPayload,
  AudioGenerationResult,
  GenerateSongJobData,
  StructuredLyrics,
} from '../types/pipeline.types';

// Stage 2 of the pipeline (specs/04-ai-generation-pipeline.md) — turns Stage 1's structured lyrics
// into an audio track via Replicate-hosted MusicGen. Satisfies AI-004.
//
// MusicGen is text-to-INSTRUMENTAL only — it does not synthesize vocals from lyrics. This app is a
// karaoke experience (Screen 3 — synced scrolling lyrics), so the generated track is the backing the
// user sings along to; `vocal_stem_url`/`beat_stem_url` stay null since MusicGen provides no stem
// separation (both are "if available" per AI-006). See the spec's Open Questions for this decision.
@Injectable()
export class AudioGenerationService {
  private readonly client: Replicate;
  private readonly model: string;

  constructor(private readonly config: ConfigService) {
    this.client = new Replicate({
      auth: this.config.get<string>('REPLICATE_API_TOKEN'),
    });
    this.model = this.config.get<string>(
      'REPLICATE_MUSICGEN_MODEL',
      'meta/musicgen',
    );
  }

  async generate(
    structured: StructuredLyrics,
    input: Pick<GenerateSongJobData, 'genre' | 'mood' | 'targetSubject'>,
  ): Promise<AudioGenerationResult> {
    const payload = this.buildPayload(structured, input);

    // MusicGen's own input schema only takes a text `prompt` (+ duration) — it has no `lyrics`/`tags`
    // fields. `payload` above is the provider-agnostic shape AI-004 mandates; we map it down here.
    const output = await this.client.run(this.model as `${string}/${string}`, {
      input: {
        prompt: payload.prompt,
        duration: DEFAULT_AUDIO_DURATION_SECONDS,
      },
    });

    return {
      audioFileUrl: this.extractAudioUrl(output),
      durationSeconds: DEFAULT_AUDIO_DURATION_SECONDS,
    };
  }

  // AI-004 — payload shape: { prompt, lyrics, tags }.
  private buildPayload(
    structured: StructuredLyrics,
    input: Pick<GenerateSongJobData, 'genre' | 'mood' | 'targetSubject'>,
  ): AudioGenerationPayload {
    const subjectPhrase = input.targetSubject
      ? ` about ${input.targetSubject}`
      : '';
    const prompt = `A ${input.mood.toLowerCase()} ${input.genre.toLowerCase()} instrumental backing track for an educational song${subjectPhrase}.`;

    const tags = [
      input.genre,
      input.mood,
      input.targetSubject,
      EDUCATIONAL_TAG,
    ].filter((tag): tag is string => Boolean(tag));

    return { prompt, lyrics: structured.lyrics, tags };
  }

  private extractAudioUrl(output: unknown): string {
    const value: unknown = Array.isArray(output)
      ? (output as unknown[])[0]
      : output;

    if (typeof value === 'string') {
      return value;
    }

    if (value && typeof value === 'object' && 'url' in value) {
      const urlProp = value.url;
      if (typeof urlProp === 'function') {
        const result: unknown = (urlProp as () => unknown).call(value);
        if (typeof result === 'string') return result;
      } else if (typeof urlProp === 'string') {
        return urlProp;
      } else if (urlProp instanceof URL) {
        return urlProp.toString();
      }
    }

    throw new BadGatewayException(
      'Audio generation returned an unexpected output shape',
    );
  }
}
