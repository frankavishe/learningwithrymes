import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { PlaylistsService } from './playlists.service';
import { PlaylistsController } from './playlists.controller';
import { Playlist } from './entities/playlist.entity';
import { PlaylistSong } from './entities/playlist-song.entity';
import { Song } from '../songs/entities/song.entity';

@Module({
  // Song repository here too (API-005 needs to verify the target song belongs to the acting
  // user) — same "declare the FK'd entity directly" pattern AiModule uses for Song.
  imports: [
    TypeOrmModule.forFeature([Playlist, PlaylistSong, Song]),
    AuthModule,
  ],
  providers: [PlaylistsService],
  controllers: [PlaylistsController],
  exports: [TypeOrmModule],
})
export class PlaylistsModule {}
