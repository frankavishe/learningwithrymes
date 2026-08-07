import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Job } from 'bullmq';
import { SongGenerationProcessor } from './song-generation.processor';
import { LyricStructuringService } from './services/lyric-structuring.service';
import { AudioGenerationService } from './services/audio-generation.service';
import { Song } from '../songs/entities/song.entity';
import { GenerateSongJobData } from './types/pipeline.types';

describe('SongGenerationProcessor', () => {
  let processor: SongGenerationProcessor;
  let lyricStructuring: { structure: jest.Mock };
  let audioGeneration: { generate: jest.Mock };
  let songs: { create: jest.Mock; save: jest.Mock };

  beforeEach(async () => {
    lyricStructuring = {
      structure: jest.fn().mockResolvedValue({
        title: 'Force and Motion',
        lyrics: '[Verse 1]\n...',
      }),
    };
    audioGeneration = {
      generate: jest.fn().mockResolvedValue({
        audioFileUrl: 'https://audio.example/track.mp3',
        durationSeconds: 60,
      }),
    };
    songs = {
      create: jest.fn((data: Partial<Song>) => data as Song),
      save: jest.fn((song: Song) => Promise.resolve({ ...song, id: 'song-1' })),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SongGenerationProcessor,
        { provide: LyricStructuringService, useValue: lyricStructuring },
        { provide: AudioGenerationService, useValue: audioGeneration },
        { provide: getRepositoryToken(Song), useValue: songs },
      ],
    }).compile();

    processor = module.get(SongGenerationProcessor);
  });

  it('runs Stage 1 then Stage 2 and persists the result to the songs table (AI-005, AI-006)', async () => {
    const jobData: GenerateSongJobData = {
      promptId: 'prompt-1',
      userId: 'user-1',
      rawText: 'F = ma',
      genre: 'Afrobeat',
      mood: 'Energetic',
      targetSubject: 'Physics',
    };
    const job = { data: jobData } as Job<GenerateSongJobData>;

    const result = await processor.process(job);

    expect(lyricStructuring.structure).toHaveBeenCalledWith({
      rawText: 'F = ma',
      genre: 'Afrobeat',
      mood: 'Energetic',
      targetSubject: 'Physics',
    });
    expect(audioGeneration.generate).toHaveBeenCalledWith(
      { title: 'Force and Motion', lyrics: '[Verse 1]\n...' },
      { genre: 'Afrobeat', mood: 'Energetic', targetSubject: 'Physics' },
    );
    expect(songs.save).toHaveBeenCalledWith(
      expect.objectContaining({
        promptId: 'prompt-1',
        userId: 'user-1',
        title: 'Force and Motion',
        generatedLyrics: '[Verse 1]\n...',
        audioFileUrl: 'https://audio.example/track.mp3',
        vocalStemUrl: null,
        beatStemUrl: null,
        durationSeconds: 60,
      }),
    );
    expect(result).toEqual({ songId: 'song-1' });
  });
});
