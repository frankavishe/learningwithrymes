import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import * as bcrypt from 'bcryptjs';
import { Repository } from 'typeorm';
import { User } from './entities/user.entity';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { JwtPayload } from './strategies/jwt.strategy';

const SALT_ROUNDS = 10;

export interface AuthResult {
  accessToken: string;
  user: Pick<User, 'id' | 'name' | 'email' | 'createdAt'>;
}

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
    private readonly jwtService: JwtService,
  ) {}

  // AUTH-001
  async register(dto: RegisterDto): Promise<AuthResult> {
    const existing = await this.users.findOne({ where: { email: dto.email } });
    if (existing) {
      throw new ConflictException('Email is already registered');
    }

    const passwordHash = await bcrypt.hash(dto.password, SALT_ROUNDS); // AUTH-004
    const user = this.users.create({
      name: dto.name,
      email: dto.email,
      passwordHash,
    });

    try {
      await this.users.save(user);
    } catch (err) {
      // Fallback for a duplicate-email race that slips past the findOne check above — the
      // `email UNIQUE` constraint (DB-001) is the real guard.
      if (this.isDuplicateEmailError(err)) {
        throw new ConflictException('Email is already registered');
      }
      throw err;
    }

    return this.buildAuthResult(user);
  }

  // AUTH-002
  async login(dto: LoginDto): Promise<AuthResult> {
    const user = await this.users.findOne({ where: { email: dto.email } });
    if (!user) {
      throw new UnauthorizedException('Invalid email or password');
    }

    const passwordMatches = await bcrypt.compare(
      dto.password,
      user.passwordHash,
    );
    if (!passwordMatches) {
      throw new UnauthorizedException('Invalid email or password');
    }

    return this.buildAuthResult(user);
  }

  private buildAuthResult(user: User): AuthResult {
    const payload: JwtPayload = { sub: user.id, email: user.email };
    return {
      accessToken: this.jwtService.sign(payload),
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        createdAt: user.createdAt,
      },
    };
  }

  private isDuplicateEmailError(err: unknown): boolean {
    return (
      typeof err === 'object' &&
      err !== null &&
      'code' in err &&
      (err as { code?: string }).code === 'ER_DUP_ENTRY'
    );
  }
}
