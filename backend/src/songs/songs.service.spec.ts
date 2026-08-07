import { NotFoundException } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SongsService } from './songs.service';
import { Song } from './entities/song.entity';
import { SongPrompt } from './entities/song-prompt.entity';
import { SongGenerationQueueService } from '../ai/song-generation-queue.service';

type MockRepo<T extends object> = Partial<
  Record<keyof Repository<T>, jest.Mock>
>;

const makeSong = (overrides: Partial<Song> = {}): Song =>
  ({
    id: 'song-1',
    promptId: 'prompt-1',
    userId: 'user-1',
    title: 'F = ma',
    generatedLyrics: '[Verse 1]\n...\n[Outro]',
    audioFileUrl: 'https://example.com/song.mp3',
    vocalStemUrl: null,
    beatStemUrl: null,
    durationSeconds: 60,
    createdAt: new Date('2026-01-01'),
    ...overrides,
  }) as Song;

describe('SongsService', () => {
  let service: SongsService;
  let songs: MockRepo<Song>;
  let songPrompts: MockRepo<SongPrompt>;
  let queueService: { enqueue: jest.Mock };
  let queryBuilder: {
    leftJoinAndSelect: jest.Mock;
    where: jest.Mock;
    andWhere: jest.Mock;
    orderBy: jest.Mock;
    getMany: jest.Mock;
  };

  beforeEach(async () => {
    queryBuilder = {
      leftJoinAndSelect: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      andWhere: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockReturnThis(),
      getMany: jest.fn().mockResolvedValue([]),
    };

    songs = {
      createQueryBuilder: jest.fn().mockReturnValue(queryBuilder),
      findOne: jest.fn(),
      delete: jest.fn(),
    };
    songPrompts = {
      create: jest.fn((data: Partial<SongPrompt>) => data as SongPrompt),
      // Mirrors real TypeORM: `save` mutates the passed entity in place with its generated id.
      save: jest.fn((p: SongPrompt) => {
        p.id = 'prompt-1';
        return Promise.resolve(p);
      }),
    };
    queueService = { enqueue: jest.fn().mockResolvedValue('job-1') };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SongsService,
        { provide: getRepositoryToken(Song), useValue: songs },
        { provide: getRepositoryToken(SongPrompt), useValue: songPrompts },
        { provide: SongGenerationQueueService, useValue: queueService },
      ],
    }).compile();

    service = module.get<SongsService>(SongsService);
  });

  it('is defined', () => {
    expect(service).toBeDefined();
  });

  describe('findAllForUser', () => {
    it('scopes the query to the user and orders newest-first (API-001)', async () => {
      await service.findAllForUser('user-1');

      expect(queryBuilder.where).toHaveBeenCalledWith('song.userId = :userId', {
        userId: 'user-1',
      });
      expect(queryBuilder.orderBy).toHaveBeenCalledWith(
        'song.createdAt',
        'DESC',
      );
      expect(queryBuilder.andWhere).not.toHaveBeenCalled();
    });

    it('adds a subject filter on the owning prompt when given (API-001)', async () => {
      await service.findAllForUser('user-1', 'Physics');

      expect(queryBuilder.andWhere).toHaveBeenCalledWith(
        'prompt.targetSubject = :subject',
        { subject: 'Physics' },
      );
    });
  });

  describe('findOneForUser', () => {
    it('returns the song when owned by the user (API-002)', async () => {
      songs.findOne!.mockResolvedValue(makeSong());

      const result = await service.findOneForUser('song-1', 'user-1');

      expect(songs.findOne).toHaveBeenCalledWith({
        where: { id: 'song-1', userId: 'user-1' },
        relations: { prompt: true },
      });
      expect(result.id).toBe('song-1');
    });

    it("throws NotFoundException for another user's song (API-002, AUTH-003)", async () => {
      songs.findOne!.mockResolvedValue(null);

      await expect(
        service.findOneForUser('song-1', 'someone-else'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('remove', () => {
    it('deletes the row after confirming ownership (API-003)', async () => {
      songs.findOne!.mockResolvedValue(makeSong());

      await service.remove('song-1', 'user-1');

      expect(songs.delete).toHaveBeenCalledWith({ id: 'song-1' });
    });

    it('propagates NotFoundException instead of deleting (API-003, AUTH-003)', async () => {
      songs.findOne!.mockResolvedValue(null);

      await expect(
        service.remove('song-1', 'someone-else'),
      ).rejects.toBeInstanceOf(NotFoundException);
      expect(songs.delete).not.toHaveBeenCalled();
    });
  });

  describe('generate', () => {
    it('persists a song_prompts row and enqueues the pipeline (API-006, AI-005)', async () => {
      const result = await service.generate('user-1', {
        text: 'F = ma',
        genre: 'Afrobeat',
        mood: 'Energetic',
        subject: 'Physics',
      });

      expect(songPrompts.save).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          rawText: 'F = ma',
          genre: 'Afrobeat',
          mood: 'Energetic',
          targetSubject: 'Physics',
        }),
      );
      expect(queueService.enqueue).toHaveBeenCalledWith({
        promptId: 'prompt-1',
        userId: 'user-1',
        rawText: 'F = ma',
        genre: 'Afrobeat',
        mood: 'Energetic',
        targetSubject: 'Physics',
      });
      expect(result).toEqual({ promptId: 'prompt-1', jobId: 'job-1' });
    });

    it('defaults targetSubject to null when no subject is given (API-006)', async () => {
      await service.generate('user-1', {
        text: 'F = ma',
        genre: 'Afrobeat',
        mood: 'Energetic',
      });

      expect(songPrompts.save).toHaveBeenCalledWith(
        expect.objectContaining({ targetSubject: null }),
      );
    });
  });
});
