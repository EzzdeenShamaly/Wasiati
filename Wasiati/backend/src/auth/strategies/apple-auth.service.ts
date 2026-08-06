import { Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import appleSignin from 'apple-signin-auth';

/**
 * Apple Sign-In doesn't fit Passport's redirect-strategy model as cleanly as Google —
 * the client (web or iOS) gets an identity token directly from Apple's SDK and hands it
 * to our backend, which verifies it server-side. So this is a plain verifier, not a
 * Passport Strategy.
 *
 * Apple stamps a different audience depending on where the token came from: native iOS
 * tokens carry the app's Bundle ID (App ID) while web/Android tokens carry the Services
 * ID. We accept any id listed in APPLE_CLIENT_IDS (falling back to APPLE_CLIENT_ID) so
 * all platforms verify against the same backend.
 */
@Injectable()
export class AppleAuthService {
  constructor(private config: ConfigService) {}

  private get audiences(): string[] {
    const list = this.config.get<string>('APPLE_CLIENT_IDS') ?? this.config.get<string>('APPLE_CLIENT_ID') ?? '';
    return list.split(',').map((s) => s.trim()).filter(Boolean);
  }

  async verifyIdentityToken(identityToken: string) {
    const audience = this.audiences;
    if (audience.length === 0) {
      throw new ServiceUnavailableException('Apple sign-in is not configured on this server.');
    }
    let payload: { sub: string; email?: string };
    try {
      payload = await appleSignin.verifyIdToken(identityToken, {
        audience: audience as any, // string[] is accepted at runtime (passed to jwt.verify)
        ignoreExpiration: false,
      });
    } catch {
      throw new UnauthorizedException('Invalid Apple identity token.');
    }
    if (!payload.email || !payload.sub) {
      throw new UnauthorizedException('Apple token is missing an email or subject.');
    }
    return { providerId: payload.sub, email: payload.email, provider: 'APPLE' as const };
  }
}
