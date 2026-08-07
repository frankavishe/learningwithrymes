import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

// API-006: POST /api/songs/generate body — becomes the song_prompts row (DB-002) the async
// pipeline (specs/04-ai-generation-pipeline.md) is enqueued from.
export class GenerateSongDto {
  // API-006 names this field `text` in the request body; persisted as song_prompts.raw_text.
  @IsString()
  @MinLength(1)
  text: string;

  // Matches song_prompts.genre / .mood length (DB-002).
  @IsString()
  @MinLength(1)
  @MaxLength(50)
  genre: string;

  @IsString()
  @MinLength(1)
  @MaxLength(50)
  mood: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  subject?: string;
}
