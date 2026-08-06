import { IsString, IsUUID, MaxLength, MinLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

/** A single user turn in the Ameen intake chat. Bounded so an oversized or non-string
 *  payload can't reach the model call — the global ValidationPipe skips inline types. */
export class IntakeMessageDto {
  @ApiProperty({ maxLength: 4000 })
  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  message: string;
}

/**
 * Reports which will a seeded conversation became.
 *
 * There is deliberately no `tier` here any more. Finalize used to take one and pass it
 * to `wills.create()`; the will is now created by the guided form, which sends the
 * tier the way a typed user's form does.
 */
export class SeededWillDto {
  @ApiProperty({ format: 'uuid' })
  @IsUUID()
  willId: string;
}
