import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { createHash, randomBytes, randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';

export interface AuthContext {
  userAgent?: string;
  ipAddress?: string;
}

export interface SessionUser {
  id: string;
  email: string;
  region: string;
  role: string;
}

/**
 * Access + refresh token lifecycle.
 *
 * - Access token: short-lived JWT (~15m), stateless, carries {sub,email,region,role}.
 * - Refresh token: opaque high-entropy string. We persist only its SHA-256 hash,
 *   never the token itself. Every use ROTATES it (new token, same familyId) and
 *   revokes the old one. Presenting an already-rotated/revoked token = reuse →
 *   the entire family is revoked (stolen-token defense).
 */
@Injectable()
export class TokenService {
  private readonly refreshTtlMs: number;
  private readonly idleTimeoutMs: number;

  constructor(
    private prisma: PrismaService,
    private jwt: JwtService,
    private config: ConfigService,
  ) {
    const days = Number(this.config.get<string>('REFRESH_TOKEN_TTL_DAYS') ?? 30);
    this.refreshTtlMs = days * 24 * 60 * 60 * 1000;
    // Idle timeout, owner's call (24 Jul 2026): coming back to an untouched tab an
    // hour later must land on a sign-in form, not on the dashboard. Two timers, both
    // needed: `refreshTtlMs` is the ABSOLUTE ceiling on a session, this is the IDLE
    // one. 0 disables it.
    const idleMinutes = Number(this.config.get<string>('SESSION_IDLE_TIMEOUT_MINUTES') ?? 60);
    this.idleTimeoutMs = Number.isFinite(idleMinutes) && idleMinutes > 0 ? idleMinutes * 60 * 1000 : 0;
  }

  get refreshCookieMaxAgeMs(): number {
    return this.refreshTtlMs;
  }

  /** How long a session may sit idle before re-authentication, in ms (0 = disabled). */
  get sessionIdleTimeoutMs(): number {
    return this.idleTimeoutMs;
  }

  private hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  signAccessToken(user: SessionUser): string {
    return this.jwt.sign({ sub: user.id, email: user.email, region: user.region, role: user.role });
  }

  /** Issue a refresh token in a NEW family (fresh login). Returns the raw token. */
  async issueRefreshToken(userId: string, ctx: AuthContext = {}, familyId?: string): Promise<string> {
    const raw = randomBytes(48).toString('base64url');
    await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: this.hash(raw),
        familyId: familyId ?? randomUUID(),
        expiresAt: new Date(Date.now() + this.refreshTtlMs),
        userAgent: ctx.userAgent,
        ipAddress: ctx.ipAddress,
      },
    });
    return raw;
  }

  /** Issue an access token plus a fresh-family refresh token in one call. */
  async issueTokenPair(user: SessionUser, ctx: AuthContext = {}) {
    const refreshToken = await this.issueRefreshToken(user.id, ctx);
    return {
      accessToken: this.signAccessToken(user),
      refreshToken,
      user,
    };
  }

  /** Rotate a presented refresh token; detect reuse and revoke the family if so. */
  async rotateRefreshToken(rawToken: string, ctx: AuthContext = {}) {
    const tokenHash = this.hash(rawToken);
    const existing = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: { user: true },
    });
    if (!existing) throw new UnauthorizedException('Invalid refresh token.');

    if (existing.revokedAt || existing.replacedById) {
      // A revoked/rotated token was replayed — treat the whole lineage as compromised.
      await this.revokeFamily(existing.familyId);
      throw new UnauthorizedException('Refresh token reuse detected. Session revoked.');
    }
    if (existing.expiresAt < new Date()) {
      throw new UnauthorizedException('Refresh token expired.');
    }

    // IDLE TIMEOUT. Rotation mints a new row on every refresh, so the age of the token
    // being presented IS the time since this session last did anything — no extra
    // column, no clock the client controls. Past the idle window the whole family goes,
    // so the stale cookie in a forgotten tab cannot be spent later either.
    //
    // Note this is why the check sits AFTER reuse detection: a replayed token is a
    // stolen-token signal and must revoke the family with that reason, whether or not
    // the session had also gone quiet.
    if (this.idleTimeoutMs > 0 && Date.now() - existing.createdAt.getTime() > this.idleTimeoutMs) {
      await this.revokeFamily(existing.familyId);
      throw new UnauthorizedException('Your session timed out. Please sign in again.');
    }

    const raw = randomBytes(48).toString('base64url');
    // Rotate ATOMICALLY. Two concurrent refreshes of the same token both pass the
    // reuse check above; the conditional updateMany lets exactly ONE win (it flips
    // revokedAt only while it is still null). The loser's count is 0 → treated as
    // reuse and the family is revoked, instead of both minting a live token.
    const replacement = await this.prisma.$transaction(async (tx) => {
      const claim = await tx.refreshToken.updateMany({
        where: { id: existing.id, revokedAt: null, replacedById: null },
        data: { revokedAt: new Date() },
      });
      if (claim.count === 0) return null;
      const created = await tx.refreshToken.create({
        data: {
          userId: existing.userId,
          tokenHash: this.hash(raw),
          familyId: existing.familyId,
          expiresAt: new Date(Date.now() + this.refreshTtlMs),
          userAgent: ctx.userAgent,
          ipAddress: ctx.ipAddress,
        },
      });
      await tx.refreshToken.update({ where: { id: existing.id }, data: { replacedById: created.id } });
      return created;
    });
    if (!replacement) {
      await this.revokeFamily(existing.familyId);
      throw new UnauthorizedException('Refresh token reuse detected. Session revoked.');
    }

    const u = existing.user;
    const sessionUser: SessionUser = { id: u.id, email: u.email, region: u.region, role: u.role };
    return {
      refreshToken: raw,
      accessToken: this.signAccessToken(sessionUser),
      user: sessionUser,
    };
  }

  async revokeFamily(familyId: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({
      where: { familyId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  /** Revoke the family a given raw token belongs to (logout). No-op if unknown. */
  async revokeByToken(rawToken: string): Promise<void> {
    const token = await this.prisma.refreshToken.findUnique({ where: { tokenHash: this.hash(rawToken) } });
    if (token) await this.revokeFamily(token.familyId);
  }

  async revokeAllForUser(userId: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }
}
