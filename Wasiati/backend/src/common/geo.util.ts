import { Region } from '@prisma/client';

/** ISO-3166 alpha-2 country -> pricing Region. Everything unlisted falls back to US (USD). */
const COUNTRY_TO_REGION: Record<string, Region> = {
  US: Region.US,
  CA: Region.CA,
  SA: Region.KSA, // Saudi Arabia's ISO code is "SA"
};

/**
 * The currency each region SHOULD be billed in — every user pays in their own
 * money. This is the intent; `resolveBillingCurrency` applies the reality check.
 */
export const REGION_CURRENCY: Record<Region, string> = {
  US: 'USD',
  CA: 'CAD',
  KSA: 'SAR',
};

/** Charged when a region's own currency is not enabled on the merchant account. */
export const FALLBACK_CURRENCY = 'USD';

/**
 * Regions where a grave must be PAID for. Burial pre-planning (the Ultimate tier) is
 * offered only here — where burial is provided free (KSA: community/state provision
 * per local custom) there is nothing to pre-pay, so Ultimate is hidden. Driven by this
 * list rather than a hardcoded US/CA check, so enabling burial in a new paid-burial
 * region is a one-line change.
 */
export const PAID_BURIAL_REGIONS: Region[] = [Region.US, Region.CA];

/** True when a grave costs money in this region — the gate for Ultimate / burial planning. */
export function regionRequiresPaidBurial(region: Region): boolean {
  return PAID_BURIAL_REGIONS.includes(region);
}

/**
 * Currencies the payment provider can actually process for us.
 *
 * Stripe presents 135+ currencies, but what a given account can charge depends on
 * its entity/capabilities, and settlement pairs must be confirmed before going
 * live. `PAYMENT_ENABLED_CURRENCIES` lists what is switched on (comma-separated).
 * Unset = assume all enabled, which is right for dev; production should set it
 * explicitly.
 */
function enabledCurrencies(): Set<string> | null {
  const raw = process.env.PAYMENT_ENABLED_CURRENCIES?.trim();
  if (!raw) return null;
  return new Set(
    raw
      .split(',')
      .map((c) => c.trim().toUpperCase())
      .filter(Boolean),
  );
}

/**
 * The currency a user in `region` is actually billed in.
 *
 * Qatar bills in QAR; if QAR is not enabled on the merchant account we fall back
 * to USD rather than failing the purchase. The same rule holds for every region —
 * nobody is ever blocked from paying because a local currency is not switched on.
 */
export function resolveBillingCurrency(region: Region): string {
  const preferred = REGION_CURRENCY[region];
  const enabled = enabledCurrencies();
  if (!enabled || enabled.has(preferred)) return preferred;
  return FALLBACK_CURRENCY;
}

/** True when the user is being charged in something other than their own currency. */
export function isFallbackCurrency(region: Region): boolean {
  return resolveBillingCurrency(region) !== REGION_CURRENCY[region];
}

/**
 * Currencies HARD-PEGGED to the US dollar, so a fallback conversion is exact and
 * needs no FX feed. QAR and SAR have held these pegs for decades.
 */
export const USD_PEG: Record<string, number> = {
  QAR: 3.64, // Qatari riyal
  SAR: 3.75, // Saudi riyal
  USD: 1,
};

/**
 * Converts a price into the fallback currency (USD).
 *
 * This exists because a price is stored in the region's own currency: Qatar's
 * Basic plan is 72500 QAR-minor. Falling back to USD by relabelling the currency
 * would charge $725 instead of ~$199. We convert instead.
 *
 * Throws for currencies without a fixed peg — guessing an FX rate to charge a
 * customer is worse than refusing.
 */
export function convertToFallbackMinor(amountMinor: number, fromCurrency: string): number {
  const from = fromCurrency.toUpperCase();
  if (from === FALLBACK_CURRENCY) return amountMinor;

  const peg = USD_PEG[from];
  if (!peg) {
    throw new Error(
      `Cannot bill ${from} in ${FALLBACK_CURRENCY}: no fixed peg is defined, and guessing an FX rate to charge a customer is not acceptable. Enable ${from} on the merchant account.`,
    );
  }
  return Math.round(amountMinor / peg);
}

/** True when a currency has a fixed USD peg and can be converted exactly. */
export function isPegged(currency: string): boolean {
  return USD_PEG[currency.toUpperCase()] !== undefined;
}

/**
 * Converts between two PEGGED currencies (via their USD pegs), returning null when
 * either side floats.
 *
 * Used for ESTIMATES only — summing a mixed-currency asset inventory for a zakat
 * figure. It returns null rather than throwing because an estimate should show the
 * user what it *could* total and disclose what it could not convert, whereas a
 * CHARGE must refuse outright (see convertToFallbackMinor).
 *
 * A floating pair (e.g. CAD -> SAR) needs a live FX rate we do not have. Guessing one
 * would silently mis-state how much zakat somebody owes.
 */
export function convertPeggedMinor(amountMinor: number, from: string, to: string): number | null {
  const f = from.toUpperCase();
  const t = to.toUpperCase();
  if (f === t) return amountMinor;

  const fromPeg = USD_PEG[f];
  const toPeg = USD_PEG[t];
  if (fromPeg === undefined || toPeg === undefined) return null;

  return Math.round((amountMinor / fromPeg) * toPeg);
}

export function countryToRegion(country?: string | null): Region {
  if (!country) return Region.US;
  return COUNTRY_TO_REGION[country.toUpperCase()] ?? Region.US;
}

/**
 * Resolves the pricing region for an ANONYMOUS storefront visitor. Precedence:
 *   1. an explicit, valid ?region= (lets a browsing visitor price-shop, and lets
 *      tests force a region)
 *   2. Cloudflare's CF-IPCountry header (set automatically when proxied) — the
 *      primary signal in production
 *   3. an X-Country override header (handy for local testing without Cloudflare)
 *   4. default US -> USD
 *
 * Mapping: US->USD, CA->CAD, SA->SAR, QA->QAR, everyone else->USD.
 *
 * EVERY input here is client-controlled and therefore spoofable (a query param, a
 * header a non-Cloudflare client can just set). That is acceptable for a visitor
 * we cannot identify — but NOT for one we can. Do not call this directly for a
 * request that might be authenticated: call `resolvePricingRegion`, which prefers
 * the account.
 */
export function resolveRegion(req: any, explicitRegion?: string): Region {
  if (explicitRegion && (Object.values(Region) as string[]).includes(explicitRegion)) {
    return explicitRegion as Region;
  }
  const headers = req?.headers ?? {};
  const country = (headers['cf-ipcountry'] as string) || (headers['x-country'] as string) || '';
  return countryToRegion(country);
}

/**
 * THE region rule for anything that prices or charges. One function, so pricing,
 * promo previews and checkout cannot drift apart.
 *
 *   · signed in  -> the user's ACCOUNT region. Full stop. Fixed at signup and
 *     bound to data residency (this deployment only holds users of its own
 *     region), so it is the truth about which market this customer belongs to —
 *     and it is OURS, not the client's.
 *   · anonymous  -> geo-IP (see resolveRegion), the best guess available.
 *
 * A signed-in user's `?region=` / CF-IPCountry is deliberately IGNORED. Otherwise
 * a KSA member on a VPN — or anyone who can type a query string — gets billed in
 * USD, which is the bug this exists to prevent: the currency a member is charged
 * must not depend on where they happen to be standing.
 */
export function resolvePricingRegion(params: {
  /** The signed-in user's `user.region`, or null/undefined when anonymous. */
  accountRegion?: Region | null;
  /** Client-supplied `?region=` — honoured for anonymous visitors only. */
  explicitRegion?: string;
  /** The request, for its geo headers — anonymous visitors only. */
  req?: any;
}): Region {
  if (params.accountRegion) return params.accountRegion;
  return resolveRegion(params.req, params.explicitRegion);
}

// --- Data residency -----------------------------------------------------------

/**
 * The region THIS deployment serves. Each region runs its own instance against
 * its own database; personal data must never cross that boundary.
 *
 * Throws rather than defaulting: a wrong default would silently write a user into
 * the wrong jurisdiction's database, which is exactly the failure we cannot have.
 */
export function deploymentRegion(): Region {
  const raw = process.env.REGION?.trim().toUpperCase();
  if (!raw || !(Object.values(Region) as string[]).includes(raw)) {
    throw new Error(
      `REGION must be one of ${Object.values(Region).join(', ')} — got "${process.env.REGION ?? '(unset)'}". ` +
        'Refusing to continue: without it a user could be written to the wrong regional database.',
    );
  }
  return raw as Region;
}

/**
 * The market regions THIS deployment accepts signups for.
 *
 * `REGION` names the shard — the jurisdiction whose infrastructure this instance
 * runs in. `SERVED_REGIONS` (comma-separated, defaults to just `REGION`) lists the
 * MARKETS it serves. The two are distinct because the launch topology is one stack
 * serving every market (no market legally requires in-country storage — plan of
 * 28 Jul 2026), while the schema and this file keep the per-region shard model so
 * standing up a dedicated KSA stack later means REMOVING `KSA` from this list here
 * and deploying a new instance — not touching application code.
 *
 * A user's `region` stays their MARKET (their pricing, their currency, Nafath vs
 * Stripe Identity); which database holds them is a deployment concern.
 */
export function servedRegions(): Region[] {
  const raw = process.env.SERVED_REGIONS?.trim();
  if (!raw) return [deploymentRegion()];
  const all = Object.values(Region) as string[];
  const parsed = raw
    .split(',')
    .map((r) => r.trim().toUpperCase())
    .filter(Boolean);
  const bad = parsed.filter((r) => !all.includes(r));
  if (bad.length) {
    // Same posture as deploymentRegion(): refuse to run half-configured rather
    // than silently narrowing who can sign up.
    throw new Error(`SERVED_REGIONS contains unknown region(s): ${bad.join(', ')}. Valid: ${all.join(', ')}.`);
  }
  return [...new Set(parsed)] as Region[];
}

export class ResidencyViolationError extends Error {
  constructor(
    readonly userRegion: Region,
    readonly deployment: Region,
  ) {
    super(
      `This service does not hold ${userRegion} accounts. Accounts for ${userRegion} must be created on the ${userRegion} service so the data stays in its own jurisdiction.`,
    );
    this.name = 'ResidencyViolationError';
  }
}

/**
 * Guards the residency boundary at the only place it can be crossed: creating a
 * user. A region this deployment does not serve must never be written into its
 * database, whichever endpoint the client happened to hit.
 */
export function assertResidency(userRegion: Region): void {
  if (!servedRegions().includes(userRegion)) {
    throw new ResidencyViolationError(userRegion, deploymentRegion());
  }
}
