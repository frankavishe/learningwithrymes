import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { JwtPayload } from '../strategies/jwt.strategy';

// AUTH-003: guarded routes read the acting user off the JWT (never a client-supplied user_id).
// Pulls the `JwtStrategy.validate` return value that Passport attaches to `request.user`.
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): JwtPayload => {
    const request = ctx.switchToHttp().getRequest<{ user: JwtPayload }>();
    return request.user;
  },
);
