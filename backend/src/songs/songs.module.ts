import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { AiModule } from '../ai/ai.module';
import { SongsService } from './songs.service';
import { SongsController } from './songs.controller';
import { Song } from './entities/song.entity';
import { SongPrompt } from './entities/song-prompt.entity';

@Module({
  // AiModule for SongGenerationQueueService (API-006 → AI-005). AiModule declares its own
  // Song repository rather than importing SongsModule, so this direction is cycle-free.
  imports: [TypeOrmModule.forFeature([Song, SongPrompt]), AuthModule, AiModule],
  providers: [SongsService],
  controllers: [SongsController],
  exports: [TypeOrmModule],
})
export class SongsModule {}
