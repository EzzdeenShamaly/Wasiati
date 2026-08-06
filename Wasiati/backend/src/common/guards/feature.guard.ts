import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { FEATURE_KEY } from '../decorators/require-feature.decorator';
import { EntitlementsService, Feature } from '../../entitlements/entitlements.service';

/**
 * Enforces @RequireFeature(...) using the central EntitlementsService, so admins
 * and comped demo accounts are allowed through without a paid subscription.
 * Must run after JwtAuthGuard (needs req.user.userId).
 */
@Injectable()
export class FeatureGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private entitlements: EntitlementsService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const feature = this.reflector.getAllAndOverride<Feature>(FEATURE_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!feature) return true;

    const { user } = context.switchToHttp().getRequest();
    if (!user?.userId) throw new ForbiddenException('Authentication required.');

    const allowed = await this.entitlements.hasFeature(user.userId, feature);
    if (!allowed) {
      throw new ForbiddenException(`Your plan does not include this feature (${feature}). Upgrade to continue.`);
    }
    return true;
  }
}
