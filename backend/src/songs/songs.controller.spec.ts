import { Test, TestingModule } from '@nestjs/testing';
import { SongsController } from './songs.controller';
import { SongsService } from './songs.service';
import { JwtPayload } from '../auth/strategies/jwt.strategy';

describe('SongsController', () => {
  let controller: SongsController;
  let service: {
    findAllForUser: jest.Mock;
    findOneForUser: jest.Mock;
    remove: jest.Mock;
    generate: jest.Mock;
  };
  const user: JwtPayload = { sub: 'user-1', email: 'test@example.com' };

  beforeEach(async () => {
    service = {
      findAllForUser: jest.fn(),
      findOneForUser: jest.fn(),
      remove: jest.fn(),
      generate: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [SongsController],
      providers: [{ provide: SongsService, useValue: service }],
    }).compile();

    controller = module.get<SongsController>(SongsController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('findAll delegates to the service with the JWT user and subject filter (API-001)', async () => {
    await controller.findAll(user, { subject: 'Physics' });
    expect(service.findAllForUser).toHaveBeenCalledWith('user-1', 'Physics');
  });

  it('findOne delegates to the service (API-002)', async () => {
    await controller.findOne('song-1', user);
    expect(service.findOneForUser).toHaveBeenCalledWith('song-1', 'user-1');
  });

  it('remove delegates to the service (API-003)', async () => {
    await controller.remove('song-1', user);
    expect(service.remove).toHaveBeenCalledWith('song-1', 'user-1');
  });

  it('generate delegates to the service (API-006)', async () => {
    const dto = { text: 'F = ma', genre: 'Afrobeat', mood: 'Energetic' };
    await controller.generate(user, dto);
    expect(service.generate).toHaveBeenCalledWith('user-1', dto);
  });
});
