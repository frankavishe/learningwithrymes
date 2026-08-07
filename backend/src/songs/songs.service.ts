import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Song } from './entities/song.entity';
import { SongPrompt } from './entities/song-prompt.entity';
import { GenerateSongDto } from './dto/generate-song.dto';
import { SongGenerationQueueService } from '../ai/song-generation-queue.service';

export interface GenerateSongResult {
  promptId: string;
  jobId: string;
}

@Injectable()
export class SongsService {
  constructor(
    @InjectRepository(Song) private readonly songs: Repository<Song>,
    @InjectRepository(SongPrompt)
    private readonly songPrompts: Repository<SongPrompt>,
    private readonly queueService: SongGenerationQueueService,
  ) {}

  // API-001 — scoped to the authenticated user; `subject` filters on the owning prompt's
  // target_subject since that's where DB-002 stores it (songs itself has no subject column).
  findAllForUser(userId: string, subject?: string): Promise<Song[]> {
    const query = this.songs
      .createQueryBuilder('song')
      .leftJoinAndSelect('song.prompt', 'prompt')
      .where('song.userId = :userId', { userId })
      .orderBy('song.createdAt', 'DESC');

    if (subject) {
      query.andWhere('prompt.targetSubject = :subject', { subject });
    }

    return query.getMany();
  }

  // API-002 — a song owned by another user is treated as not found, never leaked as 403
  // (AUTH-003).
  async findOneForUser(id: string, userId: string): Promise<Song> {
    const song = await this.songs.findOne({
      where: { id, userId },
      relations: { prompt: true },
    });
    if (!song) {
      throw new NotFoundException('Song not found');
    }
    return song;
  }

  // API-003 — removes the DB row. STORAGE-003 (Phase 6) will purge the audio objects from
  // object storage before/alongside this delete; no storage client exists yet, so only the row
  // goes for now.
  async remove(id: string, userId: string): Promise<void> {
    const song = await this.findOneForUser(id, userId);
    await this.songs.delete({ id: song.id });
  }

  // API-006 — persists the song_prompts row (DB-002) then hands it to AI-005's queue. Returns
  // as soon as the job is enqueued; generation itself runs async (specs/04-ai-generation-pipeline.md).
  async generate(
    userId: string,
    dto: GenerateSongDto,
  ): Promise<GenerateSongResult> {
    const prompt = this.songPrompts.create({
      userId,
      rawText: dto.text,
      genre: dto.genre,
      mood: dto.mood,
      targetSubject: dto.subject ?? null,
    });
    await this.songPrompts.save(prompt);

    const jobId = await this.queueService.enqueue({
      promptId: prompt.id,
      userId,
      rawText: prompt.rawText,
      genre: prompt.genre,
      mood: prompt.mood,
      targetSubject: prompt.targetSubject,
    });

    return { promptId: prompt.id, jobId };
  }
}
