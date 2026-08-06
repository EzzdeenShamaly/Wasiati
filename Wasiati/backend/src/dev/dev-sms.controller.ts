import { Controller, Get, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { NotificationsService, DevOutboxMessage } from '../notifications/notifications.service';

/**
 * DEV ONLY — a local "handset" for reading the SMS the backend just sent, in the
 * same spirit as the Mailhog inbox dev uses for email and MinIO for storage.
 *
 * This exists because OTP codes are, correctly, SMS-only: the public code endpoints
 * (witness send-code, trustee send-code, death-claim request) are unauthenticated and
 * must return a body identical for every phone, so they cannot hand back a code
 * without both leaking a consumable credential and turning the response into a
 * "is this phone attached to this will?" oracle. An e2e run on a machine with no
 * Twilio account therefore has no way to obtain a code — this gives it one WITHOUT
 * weakening the endpoints themselves.
 *
 * It is never reachable in production: DevModule is only imported when
 * NODE_ENV !== production AND OTP_DEV_ECHO=true, and env.validation refuses that flag
 * in production, so the route is absent rather than merely guarded.
 */
@ApiTags('dev')
@Controller('dev')
export class DevSmsController {
  constructor(private notifications: NotificationsService) {}

  /** Recent messages, newest first. `destination` filters to one phone number. */
  @Get('sms')
  recentSms(@Query('destination') destination?: string): DevOutboxMessage[] {
    return this.notifications.readDevOutbox(destination);
  }
}
