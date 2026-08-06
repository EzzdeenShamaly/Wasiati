import { Global, Module } from '@nestjs/common';
import { NotificationsService } from './notifications.service';

// Notifications (SMS/WhatsApp/email) is a cross-cutting concern injected by many
// feature modules (auth OTP, witnesses, trustees, death-claims, burial-estimates).
// Made @Global to match the PrismaModule pattern so consumers don't each re-import it.
@Global()
@Module({
  providers: [NotificationsService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
