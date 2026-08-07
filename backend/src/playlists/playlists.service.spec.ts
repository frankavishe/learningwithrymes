import { ConflictException, NotFoundException } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PlaylistsService } from './playlists.service';
import { Playlist } from './entities/playlist.entity';
import { PlaylistSong } from './entities/playlist-song.entity';
import { Song } from '../songs/entities/song.entity';

type MockRepo<T extends object> = Partial<
  Record<keyof Repository<T>, jest.Mock>
>;

const makePlaylist = (overrides: Partial<Playlist> = {}): Playlist =>
  ({
    id: 'playlist-1',
    userId: 'user-1',
    title: 'Physics Paper 1',
    description: null,
    createdAt: new Date('2026-01-01'),
    ...overrides,
  }) as Playlist;

const makeSong = (overrides: Partial<Song> = {}): Song =>
  ({
    id: 'song-1',
    promptId: 'prompt-1',
    userId: 'user-1',
    title: 'F = ma',
    generatedLyrics: '...',
    audioFileUrl: 'https://example.com/song.mp3',
    vocalStemUrl: null,
    beatStemUrl: null,
    durationSeconds: 60,
    createdAt: new Date('2026-01-01'),
    ...overrides,
  }) as Song;

describe('PlaylistsService', () => {
  let service: PlaylistsService;
  let playlists: MockRepo<Playlist>;
  let playlistSongs: MockRepo<PlaylistSong>;
  let songs: MockRepo<Song>;

  beforeEach(async () => {
    playlists = {
      create: jest.fn((data: Partial<Playlist>) => data as Playlist),
      save: jest.fn((p: Playlist) =>
        Promise.resolve({ ...p, id: 'playlist-1' }),
      ),
      findOne: jest.fn(),
    };
    playlistSongs = {
      create: jest.fn((data: Partial<PlaylistSong>) => data as PlaylistSong),
      save: jest.fn((ps: PlaylistSong) => Promise.resolve(ps)),
      findOne: jest.fn(),
    };
    songs = { findOne: jest.fn() };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PlaylistsService,
        { provide: getRepositoryToken(Playlist), useValue: playlists },
        { provide: getRepositoryToken(PlaylistSong), useValue: playlistSongs },
        { provide: getRepositoryToken(Song), useValue: songs },
      ],
    }).compile();

    service = module.get<PlaylistsService>(PlaylistsService);
  });

  it('is defined', () => {
    expect(service).toBeDefined();
  });

  describe('create', () => {
    it('creates a playlist scoped to the user (API-004)', async () => {
      const result = await service.create('user-1', {
        title: 'Physics Paper 1',
      });

      expect(playlists.save).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'user-1', title: 'Physics Paper 1' }),
      );
      expect(result.id).toBe('playlist-1');
    });
  });

  describe('addSong', () => {
    it('adds the song when both playlist and song belong to the user (API-005)', async () => {
      playlists.findOne!.mockResolvedValue(makePlaylist());
      songs.findOne!.mockResolvedValue(makeSong());
      playlistSongs.findOne!.mockResolvedValue(null);

      await service.addSong('playlist-1', 'user-1', { songId: 'song-1' });

      expect(playlistSongs.save).toHaveBeenCalledWith(
        expect.objectContaining({ playlistId: 'playlist-1', songId: 'song-1' }),
      );
    });

    it("404s when the playlist isn't owned by the user (API-005, AUTH-003)", async () => {
      playlists.findOne!.mockResolvedValue(null);

      await expect(
        service.addSong('playlist-1', 'someone-else', { songId: 'song-1' }),
      ).rejects.toBeInstanceOf(NotFoundException);
      expect(songs.findOne).not.toHaveBeenCalled();
    });

    it("404s when the song isn't owned by the user (API-005, AUTH-003)", async () => {
      playlists.findOne!.mockResolvedValue(makePlaylist());
      songs.findOne!.mockResolvedValue(null);

      await expect(
        service.addSong('playlist-1', 'user-1', { songId: 'song-1' }),
      ).rejects.toBeInstanceOf(NotFoundException);
      expect(playlistSongs.save).not.toHaveBeenCalled();
    });

    it('rejects adding the same song twice (API-005)', async () => {
      playlists.findOne!.mockResolvedValue(makePlaylist());
      songs.findOne!.mockResolvedValue(makeSong());
      playlistSongs.findOne!.mockResolvedValue({
        playlistId: 'playlist-1',
        songId: 'song-1',
      });

      await expect(
        service.addSong('playlist-1', 'user-1', { songId: 'song-1' }),
      ).rejects.toBeInstanceOf(ConflictException);
    });
  });
});
