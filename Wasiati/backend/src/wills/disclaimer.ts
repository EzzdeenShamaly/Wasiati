/**
 * Phase 1 legal posture: ship with a clear disclaimer rather than waiting on
 * jurisdiction-by-jurisdiction legal review of will validity (witness counts,
 * notarization rules, etc. vary by US state / Canadian province and aren't
 * yet encoded here). Bump CURRENT_DISCLAIMER_VERSION whenever the wording
 * changes — every Will row stores which version the owner saw and accepted,
 * so re-acceptance can be enforced later if the disclaimer materially changes.
 */
export const CURRENT_DISCLAIMER_VERSION = '2026-06-v1';

export const DISCLAIMER_TEXT = `Wasiati helps you draft an Islamic-inheritance-compliant will and related documents. This is not legal advice, and Wasiati is not a law firm. Requirements for a will to be legally valid (witness counts, notarization, signing formalities) vary by country, US state, and Canadian province, and have not been individually verified for your jurisdiction. We recommend having any will reviewed by a licensed attorney in your jurisdiction before relying on it.`;
