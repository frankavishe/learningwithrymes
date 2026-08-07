import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Playlist } from './entities/playlist.entity';
import { PlaylistSong } from './entities/playlist-song.entity';
import { Song } from '../songs/entities/song.entity';
import { CreatePlaylistDto } from './dto/create-playlist.dto';
import { AddSongToPlaylistDto } from './dto/add-song-to-playlist.dto';

@Injectable()
export class PlaylistsService {
  constructor(
    @InjectRepository(Playlist)
    private readonly playlists: Repository<Playlist>,
    @InjectRepository(PlaylistSong)
    private readonly playlistSongs: Repository<PlaylistSong>,
    @InjectRepository(Song) private readonly songs: Repository<Song>,
  ) {}

  // API-004
  async create(userId: string, dto: CreatePlaylistDto): Promise<Playlist> {
    const playlist = this.playlists.create({
      userId,
      title: dto.title,
      description: dto.description ?? null,
    });
    return this.playlists.save(playlist);
  }

  // API-005 — both the playlist and the song must belong to the acting user (AUTH-003); either
  // mismatch reads as 404 rather than leaking existence of another user's row.
  async addSong(
    playlistId: string,
    userId: string,
    dto: AddSongToPlaylistDto,
  ): Promise<PlaylistSong> {
    const playlist = await this.playlists.findOne({
      where: { id: playlistId, userId },
    });
    if (!playlist) {
      throw new NotFoundException('Playlist not found');
    }

    const song = await this.songs.findOne({
      where: { id: dto.songId, userId },
    });
    if (!song) {
      throw new NotFoundException('Song not found');
    }

    const existing = await this.playlistSongs.findOne({
      where: { playlistId, songId: song.id },
    });
    if (existing) {
      throw new ConflictException('Song is already in this playlist');
    }

    const entry = this.playlistSongs.create({
      playlistId,
      songId: song.id,
    });
    return this.playlistSongs.save(entry);
  }
}
