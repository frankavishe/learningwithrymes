import { Test, TestingModule } from '@nestjs/testing';
import { PlaylistsController } from './playlists.controller';
import { PlaylistsService } from './playlists.service';
import { JwtPayload } from '../auth/strategies/jwt.strategy';

describe('PlaylistsController', () => {
  let controller: PlaylistsController;
  let service: { create: jest.Mock; addSong: jest.Mock };
  const user: JwtPayload = { sub: 'user-1', email: 'test@example.com' };

  beforeEach(async () => {
    service = { create: jest.fn(), addSong: jest.fn() };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [PlaylistsController],
      providers: [{ provide: PlaylistsService, useValue: service }],
    }).compile();

    controller = module.get<PlaylistsController>(PlaylistsController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('create delegates to the service with the JWT user (API-004)', async () => {
    const dto = { title: 'Physics Paper 1' };
    await controller.create(user, dto);
    expect(service.create).toHaveBeenCalledWith('user-1', dto);
  });

  it('addSong delegates to the service (API-005)', async () => {
    const dto = { songId: 'song-1' };
    await controller.addSong('playlist-1', user, dto);
    expect(service.addSong).toHaveBeenCalledWith('playlist-1', 'user-1', dto);
  });
});
