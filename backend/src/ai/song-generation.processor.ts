import { Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import { Repository } from 'typeorm';
import { SONG_GENERATION_QUEUE } from './ai.constants';
import { LyricStructuringService } from './services/lyric-structuring.service';
import { AudioGenerationService } from './services/audio-generation.service';
import { GenerateSongJobData } from './types/pipeline.types';
import { Song } from '../songs/entities/song.entity';

// Runs Stage 1 -> Stage 2 -> persistence as a BullMQ worker (AI-005), then writes the result to the
// `songs` table (AI-006). Retries/backoff are configured where the job is enqueued
// (SongGenerationQueueService); a thrown error here fails the job and lets BullMQ retry it.
@Processor(SONG_GENERATION_QUEUE)
export class SongGenerationProcessor extends WorkerHost {
  private readonly logger = new Logger(SongGenerationProcessor.name);

  constructor(
    private readonly lyricStructuring: LyricStructuringService,
    private readonly audioGeneration: AudioGenerationService,
    @InjectRepository(Song) private readonly songs: Repository<Song>,
  ) {
    super();
  }

  async process(job: Job<GenerateSongJobData>): Promise<{ songId: string }> {
    const { promptId, userId, rawText, genre, mood, targetSubject } = job.data;
    this.logger.log(`Generating song for prompt ${promptId}`);

    const structured = await this.lyricStructuring.structure({
      rawText,
      genre,
      mood,
      targetSubject,
    });

    const audio = await this.audioGeneration.generate(structured, {
      genre,
      mood,
      targetSubject,
    });

    const song = this.songs.create({
      promptId,
      userId,
      title: structured.title,
      generatedLyrics: structured.lyrics,
      audioFileUrl: audio.audioFileUrl,
      vocalStemUrl: null,
      beatStemUrl: null,
      durationSeconds: audio.durationSeconds,
    });
    const saved = await this.songs.save(song);

    this.logger.log(`Song ${saved.id} generated for prompt ${promptId}`);
    return { songId: saved.id };
  }
}
