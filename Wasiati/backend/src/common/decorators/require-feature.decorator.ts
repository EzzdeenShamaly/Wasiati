import { SetMetadata } from '@nestjs/common';
import type { Feature } from '../../entitlements/entitlements.service';

export const FEATURE_KEY = 'required_feature';

/**
 * Gate an endpoint behind a paid feature. Combine with FeatureGuard:
 *   @UseGuards(JwtAuthGuard, FeatureGuard)
 *   @RequireFeature('aiIntake')
 * Admins and comped accounts pass automatically (see EntitlementsService).
 */
export const RequireFeature = (feature: Feature) => SetMetadata(FEATURE_KEY, feature);
