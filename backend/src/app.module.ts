import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AuthModule } from './auth/auth.module';
import { SongsModule } from './songs/songs.module';
import { PlaylistsModule } from './playlists/playlists.module';
import { User } from './auth/entities/user.entity';
import { SongPrompt } from './songs/entities/song-prompt.entity';
import { Song } from './songs/entities/song.entity';
import { Playlist } from './playlists/entities/playlist.entity';
import { PlaylistSong } from './playlists/entities/playlist-song.entity';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'mysql',
        host: config.get<string>('DB_HOST', 'localhost'),
        port: config.get<number>('DB_PORT', 3306),
        username: config.get<string>('DB_USERNAME'),
        password: config.get<string>('DB_PASSWORD'),
        database: config.get<string>('DB_DATABASE'),
        entities: [User, SongPrompt, Song, Playlist, PlaylistSong],
        // Schema is owned by db/migrations/*.sql (see specs/02-database-schema.md) — TypeORM never
        // auto-generates or alters tables.
        synchronize: false,
      }),
    }),
    AuthModule,
    SongsModule,
    PlaylistsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
