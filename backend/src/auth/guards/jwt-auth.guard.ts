import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

// Applied to every songs/playlists route per AUTH-003. Auth's own register/login routes
// (Phase 3) are the only endpoints left unguarded.
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
