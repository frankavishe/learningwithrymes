import { Test, TestingModule } from '@nestjs/testing';
import { getQueueToken } from '@nestjs/bullmq';
import { SongGenerationQueueService } from './song-generation-queue.service';
import { SONG_GENERATION_QUEUE } from './ai.constants';
import { GenerateSongJobData } from './types/pipeline.types';

describe('SongGenerationQueueService', () => {
  let service: SongGenerationQueueService;
  let queue: { add: jest.Mock };

  beforeEach(async () => {
    queue = { add: jest.fn().mockResolvedValue({ id: 'job-1' }) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SongGenerationQueueService,
        { provide: getQueueToken(SONG_GENERATION_QUEUE), useValue: queue },
      ],
    }).compile();

    service = module.get(SongGenerationQueueService);
  });

  it('enqueues the job with retry/backoff options and returns the job id (AI-005)', async () => {
    const data: GenerateSongJobData = {
      promptId: 'prompt-1',
      userId: 'user-1',
      rawText: 'F = ma',
      genre: 'Afrobeat',
      mood: 'Energetic',
      targetSubject: 'Physics',
    };

    const jobId = await service.enqueue(data);

    expect(jobId).toBe('job-1');
    expect(queue.add).toHaveBeenCalledWith(
      'generate',
      data,
      expect.objectContaining({ attempts: 2 }),
    );
  });
});
