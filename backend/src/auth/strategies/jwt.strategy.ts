import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

// JWT payload shape minted at login/register (Phase 3, AUTH-001/AUTH-002).
export interface JwtPayload {
  sub: string; // users.id
  email: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('JWT_SECRET') as string,
    });
  }

  // Return value is attached to `request.user` — downstream handlers read `req.user.sub` as the
  // acting user_id (AUTH-003: never trust a client-supplied user_id).
  validate(payload: JwtPayload): JwtPayload {
    return payload;
  }
}
