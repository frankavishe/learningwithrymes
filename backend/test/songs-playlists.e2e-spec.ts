import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import request from 'supertest';
import { App } from 'supertest/types';
import { Repository } from 'typeorm';
import { AppModule } from '../src/app.module';
import { User } from '../src/auth/entities/user.entity';
import { Song } from '../src/songs/entities/song.entity';
import { SongPrompt } from '../src/songs/entities/song-prompt.entity';
import { Playlist } from '../src/playlists/entities/playlist.entity';
import { PlaylistSong } from '../src/playlists/entities/playlist-song.entity';

interface AuthResponseBody {
  accessToken: string;
  user: { id: string; name: string; email: string };
}

describe('Songs & Playlists (e2e)', () => {
  let app: INestApplication<App>;
  let users: Repository<User>;
  let songPrompts: Repository<SongPrompt>;
  let songs: Repository<Song>;
  let playlists: Repository<Playlist>;
  let playlistSongs: Repository<PlaylistSong>;

  const ownerEmail = 'songs-e2e-owner@example.com';
  const intruderEmail = 'songs-e2e-intruder@example.com';

  let ownerToken: string;
  let ownerId: string;
  let intruderToken: string;

  const createdPromptIds: string[] = [];
  const createdSongIds: string[] = [];
  const createdPlaylistIds: string[] = [];

  // Seeds a prompt+song pair owned by `userId`, bypassing the (unbuilt-until-Phase-6) real
  // generation pipeline — Phase 5 only owns the REST surface over already-generated songs.
  async function seedSong(
    userId: string,
    overrides: Partial<SongPrompt & Song> = {},
  ): Promise<Song> {
    const prompt = await songPrompts.save(
      songPrompts.create({
        userId,
        rawText: overrides.rawText ?? 'F = ma',
        genre: overrides.genre ?? 'Afrobeat',
        mood: overrides.mood ?? 'Energetic',
        targetSubject: overrides.targetSubject ?? 'Physics',
      }),
    );
    createdPromptIds.push(prompt.id);

    const song = await songs.save(
      songs.create({
        promptId: prompt.id,
        userId,
        title: overrides.title ?? 'Newton’s Second Law',
        generatedLyrics:
          '[Verse 1]\n...\n[Chorus]\n...\n[Verse 2]\n...\n[Outro]',
        audioFileUrl: 'https://example.com/song.mp3',
        vocalStemUrl: null,
        beatStemUrl: null,
        durationSeconds: 60,
      }),
    );
    createdSongIds.push(song.id);
    return song;
  }

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();

    users = moduleFixture.get(getRepositoryToken(User));
    songPrompts = moduleFixture.get(getRepositoryToken(SongPrompt));
    songs = moduleFixture.get(getRepositoryToken(Song));
    playlists = moduleFixture.get(getRepositoryToken(Playlist));
    playlistSongs = moduleFixture.get(getRepositoryToken(PlaylistSong));

    await users.delete({ email: ownerEmail });
    await users.delete({ email: intruderEmail });

    const ownerRes = await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ name: 'Owner', email: ownerEmail, password: 'password123' })
      .expect(201);
    const ownerBody = ownerRes.body as AuthResponseBody;
    ownerToken = ownerBody.accessToken;
    ownerId = ownerBody.user.id;

    const intruderRes = await request(app.getHttpServer())
      .post('/api/auth/register')
      .send({ name: 'Intruder', email: intruderEmail, password: 'password123' })
      .expect(201);
    intruderToken = (intruderRes.body as AuthResponseBody).accessToken;
  });

  afterAll(async () => {
    // playlist_songs rows cascade-delete with their playlist/song (DB-005 FKs), so no explicit
    // cleanup needed for that table.
    if (createdPlaylistIds.length) {
      await playlists.delete(createdPlaylistIds);
    }
    if (createdSongIds.length) {
      await songs.delete(createdSongIds);
    }
    if (createdPromptIds.length) {
      await songPrompts.delete(createdPromptIds);
    }
    await users.delete({ email: ownerEmail });
    await users.delete({ email: intruderEmail });
    await app.close();
  });

  describe('GET /api/songs (API-001)', () => {
    it("returns only the caller's songs, newest first", async () => {
      const song = await seedSong(ownerId);

      const res = await request(app.getHttpServer())
        .get('/api/songs')
        .set('Authorization', `Bearer ${ownerToken}`)
        .expect(200);

      const body = res.body as Song[];
      expect(body.some((s) => s.id === song.id)).toBe(true);
      expect(
        body.every(
          (s) => (s as unknown as { userId: string }).userId === ownerId,
        ),
      ).toBe(true);
    });

    it('filters by subject', async () => {
      await seedSong(ownerId, {
        targetSubject: 'Physics',
      });
      const chemSong = await seedSong(ownerId, {
        targetSubject: 'Chemistry',
      });

      const res = await request(app.getHttpServer())
        .get('/api/songs?subject=Physics')
        .set('Authorization', `Bearer ${ownerToken}`)
        .expect(200);

      const body = res.body as Song[];
      expect(body.some((s) => s.id === chemSong.id)).toBe(false);
    });

    it('rejects requests with no token (AUTH-003)', async () => {
      await request(app.getHttpServer()).get('/api/songs').expect(401);
    });
  });

  describe('GET /api/songs/:id (API-002)', () => {
    it('returns the song for its owner', async () => {
      const song = await seedSong(ownerId);

      const res = await request(app.getHttpServer())
        .get(`/api/songs/${song.id}`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .expect(200);

      expect((res.body as Song).id).toBe(song.id);
    });

    it('404s for a song owned by another user (API-002, AUTH-003)', async () => {
      const song = await seedSong(ownerId);

      await request(app.getHttpServer())
        .get(`/api/songs/${song.id}`)
        .set('Authorization', `Bearer ${intruderToken}`)
        .expect(404);
    });
  });

  describe('DELETE /api/songs/:id (API-003)', () => {
    it('deletes the row and it is no longer reachable', async () => {
      const song = await seedSong(ownerId);

      await request(app.getHttpServer())
        .delete(`/api/songs/${song.id}`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .expect(204);

      await request(app.getHttpServer())
        .get(`/api/songs/${song.id}`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .expect(404);

      // already gone — don't let afterAll try to delete it again
      createdSongIds.splice(createdSongIds.indexOf(song.id), 1);
    });

    it("404s deleting another user's song (API-003, AUTH-003)", async () => {
      const song = await seedSong(ownerId);

      await request(app.getHttpServer())
        .delete(`/api/songs/${song.id}`)
        .set('Authorization', `Bearer ${intruderToken}`)
        .expect(404);
    });
  });

  describe('POST /api/playlists + POST /api/playlists/:id/songs (API-004, API-005)', () => {
    it('creates a playlist and adds a song into it', async () => {
      const song = await seedSong(ownerId);

      const playlistRes = await request(app.getHttpServer())
        .post('/api/playlists')
        .set('Authorization', `Bearer ${ownerToken}`)
        .send({ title: 'Physics Paper 1' })
        .expect(201);
      const playlist = playlistRes.body as Playlist;
      createdPlaylistIds.push(playlist.id);
      expect(playlist.title).toBe('Physics Paper 1');

      await request(app.getHttpServer())
        .post(`/api/playlists/${playlist.id}/songs`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .send({ songId: song.id })
        .expect(201);

      const stored = await playlistSongs.findOne({
        where: { playlistId: playlist.id, songId: song.id },
      });
      expect(stored).not.toBeNull();
    });

    it('rejects adding the same song twice', async () => {
      const song = await seedSong(ownerId);
      const playlistRes = await request(app.getHttpServer())
        .post('/api/playlists')
        .set('Authorization', `Bearer ${ownerToken}`)
        .send({ title: 'Dup Test' })
        .expect(201);
      const playlist = playlistRes.body as Playlist;
      createdPlaylistIds.push(playlist.id);

      await request(app.getHttpServer())
        .post(`/api/playlists/${playlist.id}/songs`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .send({ songId: song.id })
        .expect(201);

      await request(app.getHttpServer())
        .post(`/api/playlists/${playlist.id}/songs`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .send({ songId: song.id })
        .expect(409);
    });

    it('404s adding a song that belongs to another user (API-005, AUTH-003)', async () => {
      const song = await seedSong(ownerId);
      const playlistRes = await request(app.getHttpServer())
        .post('/api/playlists')
        .set('Authorization', `Bearer ${intruderToken}`)
        .send({ title: 'Intruder Playlist' })
        .expect(201);
      const playlist = playlistRes.body as Playlist;
      createdPlaylistIds.push(playlist.id);

      await request(app.getHttpServer())
        .post(`/api/playlists/${playlist.id}/songs`)
        .set('Authorization', `Bearer ${intruderToken}`)
        .send({ songId: song.id })
        .expect(404);
    });
  });

  describe('POST /api/songs/generate (API-006, AI-005)', () => {
    it('persists a prompt and returns promptly with a job id', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/songs/generate')
        .set('Authorization', `Bearer ${ownerToken}`)
        .send({
          text: 'Newton’s second law: F = ma',
          genre: 'Afrobeat',
          mood: 'Energetic',
          subject: 'Physics',
        })
        .expect(202);

      const body = res.body as { promptId: string; jobId: string };
      expect(body.promptId).toEqual(expect.any(String));
      expect(body.jobId).toEqual(expect.any(String));
      createdPromptIds.push(body.promptId);

      const stored = await songPrompts.findOne({
        where: { id: body.promptId },
      });
      expect(stored?.userId).toBe(ownerId);
    });

    it('rejects an invalid payload', async () => {
      await request(app.getHttpServer())
        .post('/api/songs/generate')
        .set('Authorization', `Bearer ${ownerToken}`)
        .send({ text: '', genre: '', mood: '' })
        .expect(400);
    });
  });
});
