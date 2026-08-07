import { ConfigService } from '@nestjs/config';
import { Test, TestingModule } from '@nestjs/testing';
import type * as S3Sdk from '@aws-sdk/client-s3';
import {
  CreateBucketCommand,
  HeadBucketCommand,
  PutBucketPolicyCommand,
  PutObjectCommand,
} from '@aws-sdk/client-s3';
import { StorageService } from './storage.service';

jest.mock('@aws-sdk/client-s3', () => {
  const actual = jest.requireActual<typeof S3Sdk>('@aws-sdk/client-s3');
  return { ...actual, S3Client: jest.fn() };
});

type SentCommand = { input: unknown };

describe('StorageService', () => {
  let service: StorageService;
  let send: jest.Mock<Promise<unknown>, [SentCommand]>;

  const config: Record<string, string> = {
    MINIO_ENDPOINT: 'localhost',
    MINIO_PORT: '9000',
    MINIO_USE_SSL: 'false',
    MINIO_BUCKET: 'rhythmnotes-audio',
    MINIO_PUBLIC_URL: 'http://localhost:9000',
    MINIO_ACCESS_KEY: 'admin',
    MINIO_SECRET_KEY: 'password',
  };

  beforeEach(async () => {
    send = jest.fn<Promise<unknown>, [SentCommand]>();
    const { S3Client } = jest.requireMock<typeof S3Sdk>('@aws-sdk/client-s3');
    (S3Client as unknown as jest.Mock).mockImplementation(() => ({ send }));

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        StorageService,
        {
          provide: ConfigService,
          useValue: {
            get: jest.fn((key: string, def?: unknown) => config[key] ?? def),
          },
        },
      ],
    }).compile();

    service = module.get(StorageService);
    (global as unknown as { fetch: jest.Mock }).fetch = jest.fn();
  });

  describe('onModuleInit (STORAGE-001, STORAGE-002)', () => {
    it('skips creation when the bucket already exists, then applies the public-read policy', async () => {
      send.mockResolvedValue(undefined);

      await service.onModuleInit();

      expect(send).toHaveBeenCalledTimes(2);
      expect(send.mock.calls[0][0]).toBeInstanceOf(HeadBucketCommand);
      expect(send.mock.calls[1][0]).toBeInstanceOf(PutBucketPolicyCommand);
    });

    it('creates the bucket when HeadBucket fails, then applies the public-read policy', async () => {
      send.mockRejectedValueOnce(new Error('NotFound'));
      send.mockResolvedValue(undefined);

      await service.onModuleInit();

      expect(send).toHaveBeenCalledTimes(3);
      expect(send.mock.calls[1][0]).toBeInstanceOf(CreateBucketCommand);
      expect(send.mock.calls[2][0]).toBeInstanceOf(PutBucketPolicyCommand);
    });

    it('does not throw when applying the public-read policy fails (e.g. a locked-down prod S3 bucket)', async () => {
      send.mockResolvedValueOnce(undefined); // HeadBucket
      send.mockRejectedValueOnce(new Error('AccessDenied')); // PutBucketPolicy

      await expect(service.onModuleInit()).resolves.toBeUndefined();
    });
  });

  describe('uploadFromUrl (STORAGE-001, STORAGE-002)', () => {
    it('downloads the source URL and uploads it under the bucket, returning the durable URL', async () => {
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        headers: { get: () => 'audio/mpeg' },
        arrayBuffer: () => Promise.resolve(new ArrayBuffer(4)),
      });
      send.mockResolvedValue(undefined);

      const url = await service.uploadFromUrl(
        'https://replicate.delivery/track.mp3',
      );

      expect(global.fetch).toHaveBeenCalledWith(
        'https://replicate.delivery/track.mp3',
      );
      expect(send.mock.calls[0][0]).toBeInstanceOf(PutObjectCommand);
      expect(url).toMatch(
        /^http:\/\/localhost:9000\/rhythmnotes-audio\/songs\/.+\.mp3$/,
      );
    });

    it('throws when the download fails', async () => {
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: false,
        status: 404,
      });

      await expect(
        service.uploadFromUrl('https://replicate.delivery/missing.mp3'),
      ).rejects.toThrow(/Failed to download/);
    });
  });

  describe('deleteByUrls (STORAGE-003)', () => {
    it('extracts the object key and issues a delete for each non-null URL', async () => {
      send.mockResolvedValue(undefined);

      await service.deleteByUrls([
        'http://localhost:9000/rhythmnotes-audio/songs/abc.mp3',
        null,
        undefined,
      ]);

      expect(send).toHaveBeenCalledTimes(1);
      const command = send.mock.calls[0][0];
      expect(command.input).toEqual({
        Bucket: 'rhythmnotes-audio',
        Key: 'songs/abc.mp3',
      });
    });

    it('does not throw when a delete fails', async () => {
      send.mockRejectedValue(new Error('boom'));

      await expect(
        service.deleteByUrls([
          'http://localhost:9000/rhythmnotes-audio/songs/abc.mp3',
        ]),
      ).resolves.toBeUndefined();
    });

    it('is a no-op with no URLs', async () => {
      await service.deleteByUrls([]);

      expect(send).not.toHaveBeenCalled();
    });
  });
});
