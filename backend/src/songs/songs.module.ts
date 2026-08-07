import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { AiModule } from '../ai/ai.module';
import { SongsService } from './songs.service';
import { SongsController } from './songs.controller';
import { Song } from './entities/song.entity';
import { SongPrompt } from './entities/song-prompt.entity';
import { StorageModule } from '../storage/storage.module';

@Module({
  // AiModule for SongGenerationQueueService (API-006 → AI-005). AiModule declares its own
  // Song repository rather than importing SongsModule, so this direction is cycle-free.
  // StorageModule for STORAGE-003's purge-on-delete.
  imports: [
    TypeOrmModule.forFeature([Song, SongPrompt]),
    AuthModule,
    AiModule,
    StorageModule,
  ],
  providers: [SongsService],
  controllers: [SongsController],
  exports: [TypeOrmModule],
})
export class SongsModule {}
