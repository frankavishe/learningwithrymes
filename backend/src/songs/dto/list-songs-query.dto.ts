import { IsOptional, IsString, MaxLength } from 'class-validator';

// API-001: GET /api/songs?subject=... query params.
export class ListSongsQueryDto {
  // Matches song_prompts.target_subject length (DB-002).
  @IsOptional()
  @IsString()
  @MaxLength(100)
  subject?: string;
}
