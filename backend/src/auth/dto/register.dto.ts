import { IsEmail, IsString, MaxLength, MinLength } from 'class-validator';

// AUTH-001: POST /api/auth/register body.
export class RegisterDto {
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name: string;

  @IsEmail()
  @MaxLength(150)
  email: string;

  // Min length is a scaffolding decision (not specified in specs/03-auth-api.md) — revisit if
  // product wants stronger complexity rules.
  @IsString()
  @MinLength(8)
  @MaxLength(72) // bcrypt silently truncates beyond 72 bytes
  password: string;
}
