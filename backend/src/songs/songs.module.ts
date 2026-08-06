import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { SongsService } from './songs.service';
import { SongsController } from './songs.controller';
import { Song } from './entities/song.entity';
import { SongPrompt } from './entities/song-prompt.entity';

@Module({
  imports: [TypeOrmModule.forFeature([Song, SongPrompt]), AuthModule],
  providers: [SongsService],
  controllers: [SongsController],
  exports: [TypeOrmModule],
})
export class SongsModule {}
