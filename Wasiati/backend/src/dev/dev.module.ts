import { Module } from '@nestjs/common';
import { DevSmsController } from './dev-sms.controller';
import { DevEntitlementController } from './dev-entitlement.controller';

/**
 * Local-development conveniences that must NEVER exist in a deployed environment.
 * Registered conditionally — see `DevModule.registerIfEnabled`.
 */
@Module({
  controllers: [DevSmsController, DevEntitlementController],
})
export class DevModule {
  /**
   * Returns [DevModule] only in a dev-echo environment, and [] otherwise, so the
   * /dev/* routes are ABSENT in production rather than guarded by a runtime check
   * inside the handler — a check that a future refactor could quietly drop.
   *
   * Reads process.env directly, like main.ts (Swagger gating) and geo.util
   * (deploymentRegion) already do: ConfigModule.forRoot() loads .env into
   * process.env synchronously when it is called, and it is the first entry in
   * AppModule's imports array, so the values are present by the time this runs.
   * Keep this call AFTER ConfigModule.forRoot() in that array.
   *
   * OTP_DEV_ECHO is the same switch that already governs echoing codes on the
   * authenticated step-up endpoint, and env.validation refuses it in production —
   * so this cannot be enabled there even by mistake.
   */
  static registerIfEnabled(): [typeof DevModule] | [] {
    const enabled = process.env.NODE_ENV !== 'production' && process.env.OTP_DEV_ECHO === 'true';
    return enabled ? [DevModule] : [];
  }
}
