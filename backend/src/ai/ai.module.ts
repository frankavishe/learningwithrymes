import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SONG_GENERATION_QUEUE } from './ai.constants';
import { LyricStructuringService } from './services/lyric-structuring.service';
import { AudioGenerationService } from './services/audio-generation.service';
import { SongGenerationQueueService } from './song-generation-queue.service';
import { SongGenerationProcessor } from './song-generation.processor';
import { Song } from '../songs/entities/song.entity';
import { StorageModule } from '../storage/storage.module';

@Module({
  imports: [
    BullModule.registerQueue({ name: SONG_GENERATION_QUEUE }),
    // Declared directly (rather than importing SongsModule) to avoid a circular import once
    // Phase 5's SongsModule imports AiModule to call SongGenerationQueueService.
    TypeOrmModule.forFeature([Song]),
    // Phase 6 — AudioGenerationService uploads Replicate's output into our own bucket
    // (STORAGE-001/STORAGE-002) before persisting a URL.
    StorageModule,
  ],
  providers: [
    LyricStructuringService,
    AudioGenerationService,
    SongGenerationQueueService,
    SongGenerationProcessor,
  ],
  exports: [SongGenerationQueueService],
})
export class AiModule {}
