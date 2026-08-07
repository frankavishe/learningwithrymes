import { BadGatewayException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test, TestingModule } from '@nestjs/testing';
import { GoogleGenAI } from '@google/genai';
import { LyricStructuringService } from './lyric-structuring.service';

jest.mock('@google/genai', () => ({
  GoogleGenAI: jest.fn(),
  Type: { OBJECT: 'OBJECT', STRING: 'STRING' },
}));

const VALID_LYRICS =
  '[Verse 1]\nF = ma holds the ground\n[Chorus]\nNewton found it all around\n[Verse 2]\nMomentum carries on\n[Outro]\nUntil the force is gone';

describe('LyricStructuringService', () => {
  let service: LyricStructuringService;
  let generateContent: jest.Mock;

  beforeEach(async () => {
    generateContent = jest.fn();
    (GoogleGenAI as unknown as jest.Mock).mockImplementation(() => ({
      models: { generateContent },
    }));

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        LyricStructuringService,
        {
          provide: ConfigService,
          useValue: { get: jest.fn((_key: string, def?: unknown) => def) },
        },
      ],
    }).compile();

    service = module.get(LyricStructuringService);
  });

  const input = {
    rawText: 'F = ma, the second law of motion.',
    genre: 'Afrobeat',
    mood: 'Energetic',
    targetSubject: 'Physics',
  };

  it('returns structured lyrics with exactly the four section markers, in order (AI-002)', async () => {
    generateContent.mockResolvedValue({
      text: JSON.stringify({ title: 'Force and Motion', lyrics: VALID_LYRICS }),
    });

    const result = await service.structure(input);

    expect(result.title).toBe('Force and Motion');
    expect(result.lyrics).toBe(VALID_LYRICS);
    expect(generateContent).toHaveBeenCalledTimes(1);
  });

  it('preserves verbatim academic content passed through from the model (AI-001)', async () => {
    generateContent.mockResolvedValue({
      text: JSON.stringify({ title: 'Force and Motion', lyrics: VALID_LYRICS }),
    });

    const result = await service.structure(input);

    expect(result.lyrics).toContain('F = ma');
  });

  it('retries once on malformed section markers, then succeeds (AI-002)', async () => {
    generateContent
      .mockResolvedValueOnce({
        text: JSON.stringify({ title: 'Bad', lyrics: '[Intro]\nnope' }),
      })
      .mockResolvedValueOnce({
        text: JSON.stringify({
          title: 'Force and Motion',
          lyrics: VALID_LYRICS,
        }),
      });

    const result = await service.structure(input);

    expect(result.lyrics).toBe(VALID_LYRICS);
    expect(generateContent).toHaveBeenCalledTimes(2);
  });

  it('throws after repeated malformed section markers', async () => {
    generateContent.mockResolvedValue({
      text: JSON.stringify({ title: 'Bad', lyrics: '[Intro]\nnope' }),
    });

    await expect(service.structure(input)).rejects.toBeInstanceOf(
      BadGatewayException,
    );
    expect(generateContent).toHaveBeenCalledTimes(2);
  });

  it('throws on an empty model response', async () => {
    generateContent.mockResolvedValue({ text: '' });

    await expect(service.structure(input)).rejects.toBeInstanceOf(
      BadGatewayException,
    );
  });
});
