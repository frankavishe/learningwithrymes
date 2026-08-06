import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { User } from '../../auth/entities/user.entity';
import { SongPrompt } from './song-prompt.entity';

// Matches specs/02-database-schema.md — DB-003
@Entity('songs')
export class Song {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 36, name: 'prompt_id' })
  promptId: string;

  @ManyToOne(() => SongPrompt, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'prompt_id' })
  prompt: SongPrompt;

  @Column({ type: 'varchar', length: 36, name: 'user_id' })
  userId: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ type: 'varchar', length: 150 })
  title: string;

  @Column({ type: 'text', name: 'generated_lyrics' })
  generatedLyrics: string;

  @Column({ type: 'varchar', length: 255, name: 'audio_file_url' })
  audioFileUrl: string;

  @Column({
    type: 'varchar',
    length: 255,
    name: 'vocal_stem_url',
    nullable: true,
  })
  vocalStemUrl: string | null;

  @Column({
    type: 'varchar',
    length: 255,
    name: 'beat_stem_url',
    nullable: true,
  })
  beatStemUrl: string | null;

  @Column({ type: 'int', name: 'duration_seconds', nullable: true })
  durationSeconds: number | null;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at' })
  createdAt: Date;
}
