import { Controller, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

// AUTH-003: every songs route requires a valid JWT. Actual endpoints land in Phase 5.
@Controller('songs')
@UseGuards(JwtAuthGuard)
export class SongsController {}
