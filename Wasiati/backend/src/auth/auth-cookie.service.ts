import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Request, Response } from 'express';
import { TokenService, SessionUser } from './token.service';

export const REFRESH_COOKIE = 'wasiati_refresh';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  user: SessionUser;
}

/**
 * Shapes authentication responses consistently for both the password/OAuth flow
 * (AuthController) and the passkey flow (PasskeysController):
 *  - Web:    refresh token in an httpOnly Secure cookie; body carries access + user.
 *  - Mobile: refresh token in the body for secure-storage persistence.
 * The client declares its platform via the `X-Client-Platform` header.
 */
@Injectable()
export class AuthCookieService {
  constructor(
    private config: ConfigService,
    private tokens: TokenService,
  ) {}

  isMobile(req: Request): boolean {
    const p = String(req.headers['x-client-platform'] ?? '').toLowerCase();
    return p === 'ios' || p === 'android';
  }

  /** Refresh token from the httpOnly cookie (web) or the request body (mobile). */
  readRefreshToken(req: Request, bodyToken?: string): string | undefined {
    return req.cookies?.[REFRESH_COOKIE] ?? bodyToken;
  }

  deliver(req: Request, res: Response, pair: TokenPair) {
    if (this.isMobile(req)) {
      return { accessToken: pair.accessToken, refreshToken: pair.refreshToken, user: pair.user };
    }
    this.setRefreshCookie(res, pair.refreshToken);
    return { accessToken: pair.accessToken, user: pair.user };
  }

  setRefreshCookie(res: Response, token: string): void {
    res.cookie(REFRESH_COOKIE, token, {
      httpOnly: true,
      secure: this.config.get<string>('COOKIE_SECURE') === 'true',
      sameSite: 'lax',
      path: '/auth',
      // In prod set COOKIE_DOMAIN=.wasiati.com so the httpOnly session cookie is
      // shared between app.wasiati.com and api.wasiati.com (same-site subdomains).
      // Unset in dev => host-only cookie on localhost.
      domain: this.config.get<string>('COOKIE_DOMAIN') || undefined,
      maxAge: this.tokens.refreshCookieMaxAgeMs,
    });
  }

  clearRefreshCookie(res: Response): void {
    res.clearCookie(REFRESH_COOKIE, {
      path: '/auth',
      domain: this.config.get<string>('COOKIE_DOMAIN') || undefined,
    });
  }
}
