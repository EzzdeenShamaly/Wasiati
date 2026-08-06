import {
  CanActivate,
  createParamDecorator,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  SetMetadata,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { createHash } from 'crypto';
import { ClaimRole, ClaimTokenScope } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/**
 * The header the raw claim token travels in.
 *
 * NOT `Authorization: Bearer` — deliberately. A claim token and a JWT are different
 * credentials with different blast radii, and sharing one header invites a route (or a
 * future global guard) to accept whichever it finds. Keeping them in separate headers
 * means JwtAuthGuard can never see a claim token and this guard can never see a JWT.
 * NOT a query parameter either: a token in a URL leaks into access logs, Referer headers
 * and browser history, and this one arrives by SMS in a link the holder may well share.
 */
export const CLAIM_TOKEN_HEADER = 'x-claim-token';

/**
 * A 256-bit token is 43 chars base64url. Anything wildly longer is not a token; refuse it
 * before hashing so a caller cannot make us SHA-256 a multi-megabyte header.
 */
const MAX_TOKEN_LENGTH = 512;

const CLAIM_SCOPE_KEY = 'claimTokenScope';

/**
 * Declares which scope(s) may reach a route. REQUIRED on every route behind
 * ClaimTokenGuard — the guard denies a route that declares none (see canActivate).
 */
export const ClaimScopes = (...scopes: ClaimTokenScope[]) => SetMetadata(CLAIM_SCOPE_KEY, scopes);

/** What the guard attaches to the request once a token verifies. */
export interface ClaimTokenContext {
  /** ClaimAccessToken.id — the handle the upload counter is bumped by. */
  tokenId: string;
  /**
   * The estate this token speaks for. Read OUT of the token, never off the URL or body:
   * that is the whole point of the design, so no route can be aimed at another estate.
   */
  willId: string;
  claimId: string | null;
  role: ClaimRole;
  scope: ClaimTokenScope;
  heirContactId: string | null;
}

/** The raw token as stored: SHA-256 hex. Shared with whatever mints the tokens. */
export function hashClaimToken(raw: string): string {
  return createHash('sha256').update(raw).digest('hex');
}

/** The verified token context, for routes behind ClaimTokenGuard. Mirrors @CurrentUser. */
export const ClaimToken = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): ClaimTokenContext => ctx.switchToHttp().getRequest().claimToken,
);

/**
 * Authenticates someone with NO Wasiati account by an opaque claim token, so a witness or
 * trustee can send a death certificate before any login exists.
 *
 * Shaped after OptionalJwtAuthGuard's neighbour in spirit but inverted: that guard exists to
 * let anonymous callers through, this one exists to let exactly one anonymous caller through
 * and nobody else. A missing, unknown, expired or consumed token is 401; a token that IS
 * valid but was minted for a different purpose is 403.
 *
 * Two properties carry the security of this path:
 *
 *   1. willId comes out of the TOKEN. No route behind this guard accepts a will identifier,
 *      so a token cannot be pointed at an estate it was not issued for.
 *   2. Scope is enforced per route and FAILS CLOSED. A CLAIM_SUBMIT token must never reach a
 *      portal read and a PORTAL_READ token must never reach the claim-submit upload path —
 *      the two are minted at different moments to different people. If a route forgets to
 *      declare @ClaimScopes the guard denies it outright rather than admitting every scope;
 *      RolesGuard's `no metadata → allow` default is right for an additive role check and
 *      exactly wrong here, where the guard IS the authentication.
 *
 * The lookup is a single indexed hit on the @unique tokenHash. No candidate scan, and no
 * willId is required to narrow one — the reason the column is SHA-256 and not bcrypt.
 */
@Injectable()
export class ClaimTokenGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const allowedScopes = this.reflector.getAllAndOverride<ClaimTokenScope[]>(CLAIM_SCOPE_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    // Fail closed: an undeclared route is a mistake, and the safe reading of a mistake here
    // is "no scope may enter", not "any scope may".
    if (!allowedScopes || allowedScopes.length === 0) {
      throw new ForbiddenException('This link is not valid for that action.');
    }

    const request = context.switchToHttp().getRequest();
    const raw = request.headers?.[CLAIM_TOKEN_HEADER];
    if (typeof raw !== 'string' || raw.length === 0 || raw.length > MAX_TOKEN_LENGTH) {
      throw new UnauthorizedException('This link is missing or invalid. Please use the link we sent you.');
    }

    const token = await this.prisma.claimAccessToken.findUnique({
      where: { tokenHash: hashClaimToken(raw) },
    });
    // One message for unknown / expired / consumed, so a probe cannot tell a token that
    // never existed from one that has been used.
    if (!token || token.consumedAt || token.expiresAt.getTime() <= Date.now()) {
      throw new UnauthorizedException('This link has expired or has already been used.');
    }

    if (!allowedScopes.includes(token.scope)) {
      throw new ForbiddenException('This link is not valid for that action.');
    }

    const claim: ClaimTokenContext = {
      tokenId: token.id,
      willId: token.willId,
      claimId: token.claimId,
      role: token.role,
      scope: token.scope,
      heirContactId: token.heirContactId,
    };
    // Deliberately NOT request.user: nothing downstream should mistake a token holder for an
    // authenticated account. @CurrentUser stays undefined on these routes.
    request.claimToken = claim;
    return true;
  }
}
