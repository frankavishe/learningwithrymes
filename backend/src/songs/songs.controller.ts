import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import type { JwtPayload } from '../auth/strategies/jwt.strategy';
import { SongsService, GenerateSongResult } from './songs.service';
import { ListSongsQueryDto } from './dto/list-songs-query.dto';
import { GenerateSongDto } from './dto/generate-song.dto';
import { Song } from './entities/song.entity';

// AUTH-003: every songs route requires a valid JWT.
@Controller('songs')
@UseGuards(JwtAuthGuard)
export class SongsController {
  constructor(private readonly songsService: SongsService) {}

  // API-001
  @Get()
  findAll(
    @CurrentUser() user: JwtPayload,
    @Query() query: ListSongsQueryDto,
  ): Promise<Song[]> {
    return this.songsService.findAllForUser(user.sub, query.subject);
  }

  // API-006 — declared before ':id' so 'generate' isn't swallowed by the param route.
  @Post('generate')
  @HttpCode(HttpStatus.ACCEPTED)
  generate(
    @CurrentUser() user: JwtPayload,
    @Body() dto: GenerateSongDto,
  ): Promise<GenerateSongResult> {
    return this.songsService.generate(user.sub, dto);
  }

  // API-002
  @Get(':id')
  findOne(
    @Param('id') id: string,
    @CurrentUser() user: JwtPayload,
  ): Promise<Song> {
    return this.songsService.findOneForUser(id, user.sub);
  }

  // API-003
  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @Param('id') id: string,
    @CurrentUser() user: JwtPayload,
  ): Promise<void> {
    await this.songsService.remove(id, user.sub);
  }
}
