import { Injectable } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { SONG_GENERATION_QUEUE } from './ai.constants';
import { GenerateSongJobData } from './types/pipeline.types';

// AI-005 — enqueues the pipeline to run as an async background job. Phase 5's
// `POST /api/songs/generate` handler (API-006) calls `enqueue` after persisting the `song_prompts`
// row, then returns immediately without waiting on the job.
@Injectable()
export class SongGenerationQueueService {
  constructor(
    @InjectQueue(SONG_GENERATION_QUEUE)
    private readonly queue: Queue<GenerateSongJobData>,
  ) {}

  async enqueue(data: GenerateSongJobData): Promise<string> {
    const job = await this.queue.add('generate', data, {
      attempts: 2,
      backoff: { type: 'exponential', delay: 5000 },
      removeOnComplete: true,
      removeOnFail: false,
    });
    return job.id as string;
  }
}
