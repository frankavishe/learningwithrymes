import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import type { JwtPayload } from '../auth/strategies/jwt.strategy';
import { PlaylistsService } from './playlists.service';
import { CreatePlaylistDto } from './dto/create-playlist.dto';
import { AddSongToPlaylistDto } from './dto/add-song-to-playlist.dto';
import { Playlist } from './entities/playlist.entity';
import { PlaylistSong } from './entities/playlist-song.entity';

// AUTH-003: every playlists route requires a valid JWT.
@Controller('playlists')
@UseGuards(JwtAuthGuard)
export class PlaylistsController {
  constructor(private readonly playlistsService: PlaylistsService) {}

  // API-004
  @Post()
  create(
    @CurrentUser() user: JwtPayload,
    @Body() dto: CreatePlaylistDto,
  ): Promise<Playlist> {
    return this.playlistsService.create(user.sub, dto);
  }

  // API-005
  @Post(':id/songs')
  @HttpCode(HttpStatus.CREATED)
  addSong(
    @Param('id') id: string,
    @CurrentUser() user: JwtPayload,
    @Body() dto: AddSongToPlaylistDto,
  ): Promise<PlaylistSong> {
    return this.playlistsService.addSong(id, user.sub, dto);
  }
}
