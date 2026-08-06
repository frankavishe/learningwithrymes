import { Controller, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

// AUTH-003: every playlists route requires a valid JWT. Actual endpoints land in Phase 5.
@Controller('playlists')
@UseGuards(JwtAuthGuard)
export class PlaylistsController {}
