import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/**
 * JWT auth that does NOT reject anonymous callers.
 *
 * For endpoints that are public but behave differently once you are signed in —
 * the storefront catalog being the case that matters: an anonymous visitor is
 * priced from geo-IP, a signed-in user is priced from their ACCOUNT region.
 * The plain JwtAuthGuard would 401 the anonymous visitor; leaving the endpoint
 * unguarded would blind it to the account.
 *
 * `handleRequest` is the whole point: passport hands us (err, user) and the base
 * class throws unless `user` is truthy. Here a missing/expired/invalid token is
 * simply "anonymous" — `req.user` stays undefined and the caller falls back to
 * geo. A token that IS present and valid is still fully verified by the strategy
 * (signature + expiry + pinned algorithm), so this cannot be used to forge one.
 */
@Injectable()
export class OptionalJwtAuthGuard extends AuthGuard('jwt') {
  handleRequest<TUser>(_err: unknown, user: TUser): TUser | undefined {
    return user || undefined;
  }
}
