import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PlaylistsService } from './playlists.service';
import { PlaylistsController } from './playlists.controller';
import { Playlist } from './entities/playlist.entity';
import { PlaylistSong } from './entities/playlist-song.entity';

@Module({
  imports: [TypeOrmModule.forFeature([Playlist, PlaylistSong])],
  providers: [PlaylistsService],
  controllers: [PlaylistsController],
  exports: [TypeOrmModule],
})
export class PlaylistsModule {}
