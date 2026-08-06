import { IsObject, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

/** The WebAuthn ceremony response plus the server-issued sessionId that keys the challenge in Redis. */
export class PasskeyRegisterVerifyDto {
  @ApiProperty({ description: 'sessionId returned by /register/options' })
  @IsString()
  sessionId: string;

  @ApiProperty({ type: 'object', additionalProperties: true, description: 'Authenticator attestation response' })
  @IsObject()
  response: Record<string, any>;
}

export class PasskeyLoginVerifyDto {
  @ApiProperty({ description: 'sessionId returned by /login/options' })
  @IsString()
  sessionId: string;

  @ApiProperty({ type: 'object', additionalProperties: true, description: 'Authenticator assertion response' })
  @IsObject()
  response: Record<string, any>;
}
