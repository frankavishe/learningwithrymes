import {
  Controller,
  Get,
  INestApplication,
  Module,
  UseGuards,
  ValidationPipe,
} from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import request from 'supertest';
import { App } from 'supertest/types';
import { Repository } from 'typeorm';
import { AppModule } from '../src/app.module';
import { User } from '../src/auth/entities/user.entity';
import { JwtAuthGuard } from '../src/auth/guards/jwt-auth.guard';

// Phase 5 hasn't landed real songs/playlists routes yet, so AUTH-003 (JWT guard rejects
// unauthenticated requests) has nothing real to hit. This throwaway controller reuses the same
// JwtAuthGuard the real controllers are decorated with, proving the guard mechanism itself works.
@Controller('__test-protected')
@UseGuards(JwtAuthGuard)
class ProtectedTestController {
  @Get()
  ping() {
    return { ok: true };
  }
}

@Module({
  imports: [AppModule],
  controllers: [ProtectedTestController],
})
class TestAppModule {}

interface AuthResponseBody {
  accessToken: string;
  user: { id: string; name: string; email: string; createdAt: string };
}

describe('Auth (e2e)', () => {
  let app: INestApplication<App>;
  let users: Repository<User>;
  const testEmails = [
    'auth-e2e-register@example.com',
    'auth-e2e-login@example.com',
  ];

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [TestAppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();

    users = moduleFixture.get<Repository<User>>(getRepositoryToken(User));
    await users.delete({ email: testEmails[0] });
    await users.delete({ email: testEmails[1] });
  });

  afterAll(async () => {
    await users.delete({ email: testEmails[0] });
    await users.delete({ email: testEmails[1] });
    await app.close();
  });

  describe('POST /api/auth/register (AUTH-001)', () => {
    it('creates a user and returns a usable JWT', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/auth/register')
        .send({
          name: 'Register Test',
          email: testEmails[0],
          password: 'password123',
        })
        .expect(201);

      const body = res.body as AuthResponseBody;
      expect(body.accessToken).toEqual(expect.any(String));
      expect(body.user).toMatchObject({
        name: 'Register Test',
        email: testEmails[0],
      });
      expect(body.user).not.toHaveProperty('passwordHash');

      // the returned JWT must actually authenticate against a guarded route
      await request(app.getHttpServer())
        .get('/api/__test-protected')
        .set('Authorization', `Bearer ${body.accessToken}`)
        .expect(200, { ok: true });
    });

    it('rejects a duplicate email', async () => {
      await request(app.getHttpServer())
        .post('/api/auth/register')
        .send({ name: 'Dup', email: testEmails[0], password: 'password123' })
        .expect(409);
    });

    it('rejects an invalid payload', async () => {
      await request(app.getHttpServer())
        .post('/api/auth/register')
        .send({ name: '', email: 'not-an-email', password: 'short' })
        .expect(400);
    });
  });

  describe('POST /api/auth/login (AUTH-002)', () => {
    beforeAll(async () => {
      await request(app.getHttpServer())
        .post('/api/auth/register')
        .send({
          name: 'Login Test',
          email: testEmails[1],
          password: 'password123',
        })
        .expect(201);
    });

    it('returns a valid access token for correct credentials', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/auth/login')
        .send({ email: testEmails[1], password: 'password123' })
        .expect(200);

      expect((res.body as AuthResponseBody).accessToken).toEqual(
        expect.any(String),
      );
    });

    it('rejects an incorrect password', async () => {
      await request(app.getHttpServer())
        .post('/api/auth/login')
        .send({ email: testEmails[1], password: 'wrong-password' })
        .expect(401);
    });

    it('rejects an unknown email', async () => {
      await request(app.getHttpServer())
        .post('/api/auth/login')
        .send({ email: 'nobody@example.com', password: 'password123' })
        .expect(401);
    });
  });

  describe('Protected routes (AUTH-003)', () => {
    it('rejects requests with no token', async () => {
      await request(app.getHttpServer())
        .get('/api/__test-protected')
        .expect(401);
    });

    it('rejects requests with a garbage token', async () => {
      await request(app.getHttpServer())
        .get('/api/__test-protected')
        .set('Authorization', 'Bearer not-a-real-token')
        .expect(401);
    });
  });
});
