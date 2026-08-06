import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { User } from '../../auth/entities/user.entity';

// Matches specs/02-database-schema.md — DB-002
@Entity('song_prompts')
export class SongPrompt {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 36, name: 'user_id' })
  userId: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ type: 'text', name: 'raw_text' })
  rawText: string;

  @Column({ type: 'varchar', length: 50 })
  genre: string;

  @Column({ type: 'varchar', length: 50 })
  mood: string;

  @Column({
    type: 'varchar',
    length: 100,
    name: 'target_subject',
    nullable: true,
  })
  targetSubject: string | null;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at' })
  createdAt: Date;
}
