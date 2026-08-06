import {
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryColumn,
} from 'typeorm';
import { Playlist } from './playlist.entity';
import { Song } from '../../songs/entities/song.entity';

// Matches specs/02-database-schema.md — DB-005 (composite PK, many-to-many join table)
@Entity('playlist_songs')
export class PlaylistSong {
  @PrimaryColumn({ type: 'varchar', length: 36, name: 'playlist_id' })
  playlistId: string;

  @ManyToOne(() => Playlist, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'playlist_id' })
  playlist: Playlist;

  @PrimaryColumn({ type: 'varchar', length: 36, name: 'song_id' })
  songId: string;

  @ManyToOne(() => Song, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'song_id' })
  song: Song;

  @CreateDateColumn({ type: 'timestamp', name: 'added_at' })
  addedAt: Date;
}
