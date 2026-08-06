import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import * as bcrypt from 'bcryptjs';
import { Repository } from 'typeorm';
import { AuthService } from './auth.service';
import { User } from './entities/user.entity';

type MockRepo = Partial<Record<keyof Repository<User>, jest.Mock>>;

const makeUser = (overrides: Partial<User> = {}): User => ({
  id: 'user-1',
  name: 'Test User',
  email: 'test@example.com',
  passwordHash: 'hashed',
  createdAt: new Date('2026-01-01'),
  ...overrides,
});

describe('AuthService', () => {
  let service: AuthService;
  let users: MockRepo;
  let jwtService: { sign: jest.Mock };

  beforeEach(async () => {
    users = {
      findOne: jest.fn(),
      create: jest.fn((data: Partial<User>) => data as User),
      save: jest.fn(),
    };
    jwtService = { sign: jest.fn().mockReturnValue('signed.jwt.token') };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: getRepositoryToken(User), useValue: users },
        { provide: JwtService, useValue: jwtService },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('is defined', () => {
    expect(service).toBeDefined();
  });

  describe('register', () => {
    it('hashes the password and returns a signed token (AUTH-001, AUTH-004)', async () => {
      users.findOne!.mockResolvedValue(null);
      users.save!.mockImplementation((u: User) => Promise.resolve(makeUser(u)));

      const result = await service.register({
        name: 'Test User',
        email: 'test@example.com',
        password: 'password123',
      });

      const createMock = users.create as jest.Mock<User, [Partial<User>]>;
      const savedArg = createMock.mock.calls[0][0];
      expect(savedArg.passwordHash).not.toBe('password123');
      expect(
        await bcrypt.compare('password123', savedArg.passwordHash as string),
      ).toBe(true);
      expect(result.accessToken).toBe('signed.jwt.token');
      expect(result.user).not.toHaveProperty('passwordHash');
    });

    it('rejects a duplicate email (AUTH-001)', async () => {
      users.findOne!.mockResolvedValue(makeUser());

      await expect(
        service.register({
          name: 'Dup',
          email: 'test@example.com',
          password: 'password123',
        }),
      ).rejects.toBeInstanceOf(ConflictException);
    });
  });

  describe('login', () => {
    it('returns a signed token for correct credentials (AUTH-002)', async () => {
      const passwordHash = await bcrypt.hash('password123', 10);
      users.findOne!.mockResolvedValue(makeUser({ passwordHash }));

      const result = await service.login({
        email: 'test@example.com',
        password: 'password123',
      });

      expect(result.accessToken).toBe('signed.jwt.token');
    });

    it('rejects an unknown email (AUTH-002)', async () => {
      users.findOne!.mockResolvedValue(null);

      await expect(
        service.login({ email: 'nobody@example.com', password: 'password123' }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('rejects an incorrect password (AUTH-002)', async () => {
      const passwordHash = await bcrypt.hash('password123', 10);
      users.findOne!.mockResolvedValue(makeUser({ passwordHash }));

      await expect(
        service.login({ email: 'test@example.com', password: 'wrong' }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });
  });
});
