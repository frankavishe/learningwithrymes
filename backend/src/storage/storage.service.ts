import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import {
  CreateBucketCommand,
  DeleteObjectCommand,
  HeadBucketCommand,
  PutBucketPolicyCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { AUDIO_OBJECT_PREFIX } from './storage.constants';

// Object storage layer (specs/06-audio-storage.md). Talks the S3 API so the same client works
// against MinIO in dev (self-hosted, matches the docker-compose pattern already used for
// mysql_db/redis) or AWS S3 in prod by pointing the MINIO_* env vars at S3 instead — see the
// spec's Open Questions for this resolution.
@Injectable()
export class StorageService implements OnModuleInit {
  private readonly logger = new Logger(StorageService.name);
  private readonly client: S3Client;
  private readonly bucket: string;
  private readonly publicUrl: string;

  constructor(private readonly config: ConfigService) {
    const endpoint = this.config.get<string>('MINIO_ENDPOINT', 'localhost');
    const port = this.config.get<string>('MINIO_PORT', '9000');
    const useSsl = this.config.get<string>('MINIO_USE_SSL', 'false') === 'true';
    this.bucket = this.config.get<string>('MINIO_BUCKET', 'rhythmnotes-audio');
    this.publicUrl = this.config.get<string>(
      'MINIO_PUBLIC_URL',
      `http://${endpoint}:${port}`,
    );

    this.client = new S3Client({
      endpoint: `${useSsl ? 'https' : 'http'}://${endpoint}:${port}`,
      forcePathStyle: true, // required for MinIO's path-style bucket addressing
      region: 'us-east-1', // ignored by MinIO, required by the SDK
      credentials: {
        accessKeyId: this.config.get<string>('MINIO_ACCESS_KEY', ''),
        secretAccessKey: this.config.get<string>('MINIO_SECRET_KEY', ''),
      },
    });
  }

  // STORAGE-001 — makes sure the bucket exists before anything tries to write to it; safe to run
  // on every boot since HeadBucket short-circuits once it's already there.
  async onModuleInit(): Promise<void> {
    try {
      await this.client.send(new HeadBucketCommand({ Bucket: this.bucket }));
    } catch {
      await this.client.send(new CreateBucketCommand({ Bucket: this.bucket }));
      this.logger.log(`Created bucket "${this.bucket}"`);
    }
    await this.applyPublicReadPolicy();
  }

  // STORAGE-002 — a MinIO/S3 bucket is private by default, which would make the
  // `audio_file_url` written to the songs row unplayable by the mobile client (Phase 10) without
  // per-request presigned URLs. These are generated audio tracks, not sensitive data, so
  // dev/self-hosted MinIO grants public GET on objects so the stored URL is directly streamable.
  // Best-effort: against real AWS S3 in prod, the app's IAM credentials likely can't (and
  // shouldn't need to) change bucket policy — that's infra-managed instead — so a failure here is
  // only logged, not fatal.
  private async applyPublicReadPolicy(): Promise<void> {
    try {
      await this.client.send(
        new PutBucketPolicyCommand({
          Bucket: this.bucket,
          Policy: JSON.stringify({
            Version: '2012-10-17',
            Statement: [
              {
                Effect: 'Allow',
                Principal: '*',
                Action: ['s3:GetObject'],
                Resource: [`arn:aws:s3:::${this.bucket}/*`],
              },
            ],
          }),
        }),
      );
    } catch (err) {
      this.logger.warn(
        `Could not apply public-read policy to bucket "${this.bucket}": ${String(err)}`,
      );
    }
  }

  // STORAGE-001/STORAGE-002 — downloads the provider's (e.g. Replicate's) generated audio and
  // re-uploads it into our own bucket, so the app doesn't depend on a third party's URL staying
  // valid. Returns the durable URL to persist on the songs row.
  async uploadFromUrl(
    sourceUrl: string,
    prefix: string = AUDIO_OBJECT_PREFIX,
  ): Promise<string> {
    const response = await fetch(sourceUrl);
    if (!response.ok) {
      throw new Error(
        `Failed to download generated audio from ${sourceUrl}: ${response.status}`,
      );
    }
    const body = Buffer.from(await response.arrayBuffer());
    const contentType = response.headers.get('content-type') ?? 'audio/mpeg';
    const key = `${prefix}/${randomUUID()}.mp3`;

    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: body,
        ContentType: contentType,
      }),
    );

    return `${this.publicUrl}/${this.bucket}/${key}`;
  }

  // STORAGE-003 — best-effort purge of every object a song references. Deleting a key that
  // doesn't exist is a no-op under the S3 API, so this is safe to call on rows seeded outside
  // this service (e.g. pre-Phase-6 fixtures) or with URLs that don't belong to our bucket at all.
  async deleteByUrls(urls: Array<string | null | undefined>): Promise<void> {
    const keys = urls
      .filter((url): url is string => Boolean(url))
      .map((url) => this.extractKey(url));

    await Promise.all(
      keys.map((key) =>
        this.client
          .send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }))
          .catch((err: unknown) => {
            this.logger.warn(`Failed to purge object "${key}": ${String(err)}`);
          }),
      ),
    );
  }

  private extractKey(url: string): string {
    const pathname = new URL(url).pathname.replace(/^\/+/, '');
    const bucketPrefix = `${this.bucket}/`;
    return pathname.startsWith(bucketPrefix)
      ? pathname.slice(bucketPrefix.length)
      : pathname;
  }
}
