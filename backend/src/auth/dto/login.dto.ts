import { IsEmail, IsString, MinLength } from 'class-validator';

// AUTH-002: POST /api/auth/login body.
export class LoginDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(1)
  password: string;
}
