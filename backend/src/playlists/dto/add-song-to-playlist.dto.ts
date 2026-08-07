import { IsUUID } from 'class-validator';

// API-005: POST /api/playlists/:id/songs body.
export class AddSongToPlaylistDto {
  @IsUUID()
  songId: string;
}
