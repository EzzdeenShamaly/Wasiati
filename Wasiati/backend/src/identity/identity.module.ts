import { Logger, Module } from '@nestjs/common';
import { IdentityService } from './identity.service';
import { IdentityController } from './identity.controller';
import { IDENTITY_PROVIDER, IdentityProviderPort } from './identity-provider.interface';
import { UnconfiguredIdentityProvider } from './providers/unconfigured-identity.provider';
import { SumsubIdentityProvider } from './providers/sumsub-identity.provider';
import { StripeIdentityProvider } from './providers/stripe-identity.provider';

@Module({
  controllers: [IdentityController],
  providers: [
    IdentityService,
    StripeIdentityProvider,
    SumsubIdentityProvider,
    UnconfiguredIdentityProvider,
    {
      provide: IDENTITY_PROVIDER,
      inject: [StripeIdentityProvider, SumsubIdentityProvider, UnconfiguredIdentityProvider],
      /**
       * Stripe Identity is the US/CA vendor (docs/DECISIONS.md §13, which supersedes
       * the §7 choice of Sumsub). Sumsub stays wired as a fallback so an environment
       * already carrying its credentials keeps working, and neither being present
       * falls through to the adapter that refuses with a 503 — never to one that
       * silently approves.
       *
       * `configured` is credential SHAPE, not a live API call: this runs at boot and
       * must not block or crash on a placeholder key.
       */
      useFactory: (
        stripe: StripeIdentityProvider,
        sumsub: SumsubIdentityProvider,
        unconfigured: UnconfiguredIdentityProvider,
      ): IdentityProviderPort => {
        if (stripe.configured) {
          Logger.log('Identity verification: Stripe Identity', 'IdentityModule');
          return stripe;
        }
        if (sumsub.configured) {
          Logger.warn(
            'Identity verification: Sumsub (fallback) — Stripe Identity is the decided ' +
              'vendor; set STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET to use it.',
            'IdentityModule',
          );
          return sumsub;
        }
        Logger.warn(
          'Identity verification: NOT CONFIGURED — /identity/verification-session returns 503. ' +
            'Set STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET (both are required: the outcome ' +
            'arrives only by signed webhook) to enable it.',
          'IdentityModule',
        );
        return unconfigured;
      },
    },
  ],
  exports: [IdentityService],
})
export class IdentityModule {}
