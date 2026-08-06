import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { OtpService } from './otp.service';
import { GoogleStrategy } from './strategies/google.strategy';
import { GoogleAuthService } from './strategies/google-auth.service';
import { AppleAuthService } from './strategies/apple-auth.service';
import { MicrosoftAuthService } from './strategies/microsoft-auth.service';
import { JwtStrategy } from './strategies/jwt.strategy';
import { PasskeysService } from './passkeys.service';
import { PasskeysController } from './passkeys.controller';
import { TokenService } from './token.service';
import { AuthCookieService } from './auth-cookie.service';
import { AccountRecoveryService } from './account-recovery.service';
import { TotpService } from './totp.service';
import { RecoveryCodesService } from './recovery-codes.service';
import { MailModule } from '../mail/mail.module';

// The passport-google-oauth20 Strategy throws at construction if clientID is empty.
// Register it only when Google is actually configured so the app still boots in
// environments (dev, CI, regions without Google) where those creds are absent.
// The client-driven /auth/login/google endpoint does its own token exchange and
// does not depend on this passport strategy.
const googleStrategyProvider = {
  provide: GoogleStrategy,
  useFactory: (config: ConfigService) =>
    config.get<string>('GOOGLE_CLIENT_ID') ? new GoogleStrategy(config) : null,
  inject: [ConfigService],
};

@Module({
  imports: [
    PassportModule,
    MailModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('SESSION_SECRET'),
        // Short-lived access token; long-lived rotating refresh tokens live in the DB.
        signOptions: { expiresIn: config.get<string>('ACCESS_TOKEN_TTL') ?? '15m', algorithm: 'HS256' },
      }),
    }),
  ],
  controllers: [AuthController, PasskeysController],
  providers: [AuthService, OtpService, TokenService, AuthCookieService, AccountRecoveryService, TotpService, RecoveryCodesService, googleStrategyProvider, GoogleAuthService, AppleAuthService, MicrosoftAuthService, JwtStrategy, PasskeysService],
  exports: [AuthService, OtpService, TokenService],
})
export class AuthModule {}
