import { Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createRemoteJWKSet, jwtVerify, JWTPayload } from 'jose';

/**
 * Microsoft (Entra ID / Azure AD) sign-in — like Apple, the client obtains an
 * id_token from Microsoft's MSAL SDK and hands it to us; we verify it server-side.
 *
 * Verification: signature against Microsoft's published JWKS, audience === our app's
 * client id, and issuer === the ONE tenant we are locked to.
 *
 * SECURITY — this provider is deliberately single-tenant only. We must NOT accept the
 * multi-tenant `common`/`organizations`/`consumers` authorities: `loginWithOAuth` links
 * an OAuth identity to an existing account by email, so if we accepted tokens from any
 * Entra tenant, an attacker could stand up their own tenant, mint a token carrying the
 * victim's email, and take over the account. Requiring a specific tenant means only
 * identities from an org we trust can sign in. We also require the verified `email`
 * claim and never fall back to `preferred_username`, which Microsoft documents as
 * mutable, unverified, and unsafe for authorization.
 */
const MULTI_TENANT_AUTHORITIES = new Set(['common', 'organizations', 'consumers']);

@Injectable()
export class MicrosoftAuthService {
  // Lazily built so the app boots without Microsoft configured; the JWKS endpoint is
  // tenant-agnostic (Microsoft signs all v2 tokens with the same key set).
  private jwks?: ReturnType<typeof createRemoteJWKSet>;

  constructor(private config: ConfigService) {}

  private get clientId(): string | undefined {
    return this.config.get<string>('MICROSOFT_CLIENT_ID');
  }

  /** The single tenant we accept tokens from, or undefined if misconfigured. */
  private get tenant(): string | undefined {
    const t = this.config.get<string>('MICROSOFT_TENANT')?.trim();
    if (!t || MULTI_TENANT_AUTHORITIES.has(t.toLowerCase())) return undefined;
    return t;
  }

  private getJwks(tenant: string) {
    if (!this.jwks) {
      this.jwks = createRemoteJWKSet(
        new URL(`https://login.microsoftonline.com/${tenant}/discovery/v2.0/keys`),
      );
    }
    return this.jwks;
  }

  async verifyIdToken(idToken: string) {
    if (!this.clientId) {
      // Configured-or-clean-error, never a broken sign-in.
      throw new ServiceUnavailableException('Microsoft sign-in is not configured on this server.');
    }
    const tenant = this.tenant;
    if (!tenant) {
      // Refuse to run in a takeover-prone multi-tenant mode. Ops must pin a tenant id.
      throw new ServiceUnavailableException(
        'Microsoft sign-in requires MICROSOFT_TENANT to be pinned to a single tenant id.',
      );
    }

    const expectedIssuer = `https://login.microsoftonline.com/${tenant}/v2.0`;
    let payload: JWTPayload;
    try {
      ({ payload } = await jwtVerify(idToken, this.getJwks(tenant), {
        audience: this.clientId,
        issuer: expectedIssuer, // exact match — not a wildcard over any tenant
      }));
    } catch {
      throw new UnauthorizedException('Invalid Microsoft identity token.');
    }

    // Require the verified `email` claim. Never fall back to `preferred_username`
    // (mutable + unverified — using it as an identity key enables account takeover).
    const email = payload.email as string | undefined;
    if (!email || !payload.sub) {
      throw new UnauthorizedException('Microsoft token is missing a verified email or subject.');
    }
    return { providerId: payload.sub, email, provider: 'MICROSOFT' as const };
  }
}
