import { Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createRemoteJWKSet, jwtVerify, JWTPayload } from 'jose';

/**
 * Verifies a Google ID token server-side. The Flutter client obtains the id_token
 * from the google_sign_in SDK and posts it here — we must NOT trust a client-supplied
 * email/subject, so we check Google's signature, issuer, and audience ourselves.
 *
 * Web, iOS, and Android each get their own OAuth client id from Google, and the
 * id_token's `aud` is whichever one requested it — so we accept any id listed in
 * GOOGLE_CLIENT_IDS (falling back to GOOGLE_CLIENT_ID).
 */
@Injectable()
export class GoogleAuthService {
  private readonly jwks = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));

  constructor(private config: ConfigService) {}

  private get audiences(): string[] {
    const list = this.config.get<string>('GOOGLE_CLIENT_IDS') ?? this.config.get<string>('GOOGLE_CLIENT_ID') ?? '';
    return list.split(',').map((s) => s.trim()).filter(Boolean);
  }

  async verifyIdToken(idToken: string) {
    const audiences = this.audiences;
    if (audiences.length === 0) {
      throw new ServiceUnavailableException('Google sign-in is not configured on this server.');
    }
    let payload: JWTPayload;
    try {
      ({ payload } = await jwtVerify(idToken, this.jwks, {
        issuer: ['https://accounts.google.com', 'accounts.google.com'],
        audience: audiences,
      }));
    } catch {
      throw new UnauthorizedException('Invalid Google identity token.');
    }
    // Google sets email_verified=false for some accounts; only trust verified emails.
    if (payload.email_verified === false) {
      throw new UnauthorizedException('Google account email is not verified.');
    }
    const email = payload.email as string;
    if (!email || !payload.sub) {
      throw new UnauthorizedException('Google token is missing an email or subject.');
    }
    return { providerId: payload.sub, email, provider: 'GOOGLE' as const };
  }
}
