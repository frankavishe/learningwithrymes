import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

// API-004: POST /api/playlists body.
export class CreatePlaylistDto {
  // Matches playlists.title length (DB-004).
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  title: string;

  @IsOptional()
  @IsString()
  description?: string;
}
