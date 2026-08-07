import { BadGatewayException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test, TestingModule } from '@nestjs/testing';
import Replicate from 'replicate';
import { AudioGenerationService } from './audio-generation.service';
import { DEFAULT_AUDIO_DURATION_SECONDS } from '../ai.constants';
import { StorageService } from '../../storage/storage.service';

jest.mock('replicate', () => jest.fn());

describe('AudioGenerationService', () => {
  let service: AudioGenerationService;
  let run: jest.Mock;
  let storage: { uploadFromUrl: jest.Mock };

  beforeEach(async () => {
    run = jest.fn();
    (Replicate as unknown as jest.Mock).mockImplementation(() => ({ run }));
    storage = {
      uploadFromUrl: jest.fn((url: string) =>
        Promise.resolve(url.replace('replicate.delivery', 'localhost:9000')),
      ),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AudioGenerationService,
        {
          provide: ConfigService,
          useValue: { get: jest.fn((_key: string, def?: unknown) => def) },
        },
        { provide: StorageService, useValue: storage },
      ],
    }).compile();

    service = module.get(AudioGenerationService);
  });

  const structured = {
    title: 'Force and Motion',
    lyrics: '[Verse 1]\nF = ma\n[Chorus]\n...\n[Verse 2]\n...\n[Outro]\n...',
  };
  const input = {
    genre: 'Afrobeat',
    mood: 'Energetic',
    targetSubject: 'Physics',
  };

  it('builds the {prompt, lyrics, tags} shape and calls the audio-gen API (AI-004)', async () => {
    run.mockResolvedValue('https://replicate.delivery/track.mp3');

    const result = await service.generate(structured, input);

    expect(run).toHaveBeenCalledTimes(1);
    const [model, options] = run.mock.calls[0] as [
      string,
      { input: { prompt: string; duration: number } },
    ];
    expect(model).toBe('meta/musicgen');
    expect(options.input.prompt).toContain('afrobeat');
    expect(options.input.duration).toBe(DEFAULT_AUDIO_DURATION_SECONDS);
    expect(result.durationSeconds).toBe(DEFAULT_AUDIO_DURATION_SECONDS);
  });

  it("re-uploads the provider's URL into our own storage (STORAGE-001, STORAGE-002)", async () => {
    run.mockResolvedValue('https://replicate.delivery/track.mp3');

    const result = await service.generate(structured, input);

    expect(storage.uploadFromUrl).toHaveBeenCalledWith(
      'https://replicate.delivery/track.mp3',
    );
    expect(result.audioFileUrl).toBe('https://localhost:9000/track.mp3');
  });

  it('extracts the URL from an array output', async () => {
    run.mockResolvedValue(['https://replicate.delivery/track.mp3']);

    await service.generate(structured, input);

    expect(storage.uploadFromUrl).toHaveBeenCalledWith(
      'https://replicate.delivery/track.mp3',
    );
  });

  it('extracts the URL from a FileOutput-style object with a url() method', async () => {
    run.mockResolvedValue({
      url: () => 'https://replicate.delivery/track.mp3',
    });

    await service.generate(structured, input);

    expect(storage.uploadFromUrl).toHaveBeenCalledWith(
      'https://replicate.delivery/track.mp3',
    );
  });

  it('throws on an unrecognized output shape', async () => {
    run.mockResolvedValue({ nothingUseful: true });

    await expect(service.generate(structured, input)).rejects.toBeInstanceOf(
      BadGatewayException,
    );
    expect(storage.uploadFromUrl).not.toHaveBeenCalled();
  });
});
