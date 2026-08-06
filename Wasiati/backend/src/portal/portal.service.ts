import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ClaimRole, ClaimTokenScope, DeathClaimStatus, TrusteeStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { OtpService } from '../auth/otp.service';
import { FilesService } from '../files/files.service';
import { AuditService } from '../common/audit/audit.service';
// ONE token seam for the whole product: the same generator and the same hash the
// claim-submit path uses. A second copy would mean two 43-char strings that look alike and
// verify differently.
import { ClaimTokenContext, hashClaimToken } from '../death-claims/claim-token.guard';
import { generateClaimToken } from '../death-claims/death-claims.service';
import { WillDocumentService, WillDocumentOptions } from '../wills/will-document.service';
import { normalizePhone, phonesMatch } from '../common/phone.util';
import { PortalRole } from './portal.dto';
import { RedisService } from '../redis/redis.service';

/** OtpCode.purpose for a portal sign-in. Its own purpose, so no other flow's code fits. */
export const PORTAL_OTP_PURPOSE = 'portal_login';

/**
 * Sign-in codes sent to ONE destination, per rolling hour and day. Looser than the claim
 * lookup's (3/hour, 10/day) because an heir legitimately signs in again and again over the
 * 90-day retrieval window, where a lookup happens once — but bounded, because every code is
 * a billed message and a supersession of the previous one.
 */
const PORTAL_START_LIMITS = {
  perDestinationPerHour: 5,
  perDestinationPerDay: 20,
};

/**
 * The ONE thing a caller is ever told about a failed portal sign-in.
 *
 * OtpService.verify throws three DIFFERENT BadRequestExceptions — 'No pending code for
 * this destination.', 'Code has expired.', 'Too many incorrect attempts...' — and returns
 * false for a wrong code. Ported straight through, those four outcomes are an enumeration
 * oracle on a PUBLIC endpoint: 'No pending code' for an address nobody asked a code for
 * versus 'Code has expired' for one that did tells an attacker which email addresses are
 * named on a dead person's will. That is the same oracle death-claims/lookup was rebuilt
 * to close, and it would be pointless to close it there and reopen it here.
 *
 * Every failure — unknown party, no code pending, expired, attempt cap burned, plain wrong
 * — comes back as this string. Pinned by portal-otp-uniform.spec.ts.
 */
export const PORTAL_OTP_ERROR_MESSAGE = 'Invalid or expired code.';

/**
 * The ONE thing a portal holder is told when the estate is not theirs to read yet.
 *
 * Constant across ALL FOUR non-released statuses (SUBMITTED, UNDER_REVIEW, APPROVED,
 * REJECTED) and across a claim that has vanished. If the content endpoints answered
 * differently per status they would become a progress tracker: an heir — or anyone holding
 * their inbox — could poll /portal/will and watch a claim advance toward release. Status is
 * available deliberately and in exactly one place, GET /portal/claim, which is the screen
 * the prototype designs for it.
 */
export const PORTAL_NOT_RELEASED_MESSAGE = 'This will has not been released yet.';

/**
 * How long a portal session lasts. Much shorter than a claim-submit link (7 days): that
 * link has to survive a bereaved family getting to it, while this one is a live bearer
 * credential to a released estate sitting in a browser tab.
 */
const DEFAULT_PORTAL_TOKEN_TTL_HOURS = 12;

/**
 * Which claim a portal sign-in binds to when (role, email) matches more than one —
 * duplicate claims on one will, or one person named on several estates. Lower wins.
 * See resolveParty for why raw recency was a deadlock.
 */
const PORTAL_CLAIM_PRIORITY: Record<DeathClaimStatus, number> = {
  [DeathClaimStatus.APPROVED]: 0, // the heir roll-call is live — confirmations gate release
  [DeathClaimStatus.RELEASED]: 1, // a readable estate on a 90-day purge clock
  [DeathClaimStatus.UNDER_REVIEW]: 2,
  [DeathClaimStatus.SUBMITTED]: 3,
  [DeathClaimStatus.REJECTED]: 4, // shown only when nothing live exists anywhere
};

/** Case-insensitive email equality; a blank never matches a blank. */
function emailsMatch(a?: string | null, b?: string | null): boolean {
  if (!a || !b) return false;
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}

/**
 * House style from NotificationsService.maskDestination: never write a full phone number
 * or address into a log or an audit row. The audit answers "which party", by id; the
 * masked contact is there only to make a row readable by a human reviewing it.
 */
function maskContact(to: string | null | undefined): string | undefined {
  if (!to) return undefined;
  return to.length <= 4 ? '****' : `***${to.slice(-4)}`;
}

/** Where a portal read came from. Recorded on the audit row, and on an heir confirmation. */
export interface PortalRequestMeta {
  ipAddress?: string;
  userAgent?: string;
}

/** A party resolved from (role, email) — the only identity the public routes work with. */
interface ResolvedPortalParty {
  claimId: string;
  claimStatus: DeathClaimStatus;
  willId: string;
  estateName: string;
  /** WillHeirContact.id or Trustee.id — which roster row matched. */
  partyId: string;
  phone: string | null;
  email: string | null;
}

/**
 * The heir & trustee portal: read-only access to a released estate for people who have NO
 * Wasiati account and never will.
 *
 * This module is the answer to a hole that made release() a dead end. release() marked the
 * claim RELEASED, started a 90-day purge clock and emailed the witnesses and trustees
 * "please sign in and download whatever you need" — but no heir was contacted at all, and
 * none of these people has a sign-in to use. Ninety days later the purge job erased the
 * estate that had just been "released". The portal is the hand-over that sentence promised.
 *
 * Three properties carry it:
 *
 *   1. The session credential is OPAQUE, never a JWT. JwtStrategy accepts any HS256 token
 *      signed with SESSION_SECRET and maps `sub` to a userId with no type discrimination,
 *      so a JWT minted here would be replayable at EVERY JwtAuthGuard route in the product
 *      — an heir reading a will would hold an account session. Pinned by a test that feeds
 *      a minted portal token to JwtStrategy and requires it to fail.
 *   2. willId comes out of the TOKEN on every route. No portal endpoint accepts a will
 *      identifier in a path, a query or a body, so a token cannot be aimed at another
 *      estate. That is the whole scoping answer; there is no per-route ownership check to
 *      forget.
 *   3. Content is gated by assertReleased() with ONE constant 403, so the portal cannot be
 *      used to watch a claim progress.
 *
 * THE VAULT IS EXCLUDED, permanently and by design. Vault items are end-to-end encrypted
 * under a passphrase the server never holds, and the product promises "not even by us" can
 * recover them. There is no server-side plaintext to hand an heir, so this module neither
 * reads vault rows nor says a word about them. The vault reaches the trustee by recovery
 * code, out of band — DECISIONS §19.
 */
@Injectable()
export class PortalService {
  private readonly logger = new Logger(PortalService.name);

  constructor(
    private prisma: PrismaService,
    private otp: OtpService,
    private files: FilesService,
    private audit: AuditService,
    private config: ConfigService,
    private documents: WillDocumentService,
    private redis: RedisService,
  ) {}

  // --- Sign-in ----------------------------------------------------------------

  /**
   * Sends a sign-in code to the contact ON FILE for the party this (role, email) names.
   *
   * ALWAYS `{ sent: true }`, byte-identical, for: no such party, a party on a will with no
   * claim, a real party, and an internal failure. Like death-claims/lookup, the response is
   * not a channel — answering "no such heir" here would let anyone test whether an address
   * is named on a dead person's will.
   *
   * The code goes to the roster's phone by SMS when there is one ("the 6-digit code sent to
   * your registered mobile", per the prototype) and to the roster's email otherwise. Never
   * to anything the caller typed beyond the address used to FIND the party: the email is a
   * lookup key, not a delivery target of the caller's choosing.
   */
  async start(role: PortalRole, email: string): Promise<{ sent: true }> {
    try {
      const party = await this.resolveParty(role, email);
      if (party) {
        const destination = party.phone ? normalizePhone(party.phone) : (party.email ?? '');
        if (destination && (await this.mayIssuePortalCode(destination))) {
          await this.otp.issue(
            destination,
            PORTAL_OTP_PURPOSE,
            undefined,
            destination.includes('@') ? 'email' : 'sms',
          );
        } else if (!destination) {
          this.logger.warn(`Portal start matched party ${party.partyId} with no contact on file.`);
        }
      }
    } catch (e) {
      // Log, never surface. An exception escaping here becomes a 500, and a 500 on one
      // address next to a 200 on another is precisely the oracle the constant response
      // exists to close.
      this.logger.error(`Portal start failed internally: ${(e as Error).message}`);
    }
    return { sent: true };
  }

  /**
   * A ceiling on codes sent to ONE destination, which an IP-rotating attacker cannot shed.
   *
   * The @Throttle on POST /portal/start is keyed by IP, so it limits a caller, not a
   * target. Nothing limited the target — and OtpService.verify reads only the NEWEST
   * unconsumed code for a (destination, purpose) pair. So repeated calls naming one heir's
   * address supersede that heir's real code: whatever arrived a moment ago stops being the
   * one the server will check. At a low rate that is spam and confusion; at the rate IP
   * rotation allows it is an effective lockout of a grieving family from a released will,
   * and it bills a message for every attempt — $0.1949 each in KSA.
   *
   * Modelled directly on the claim lookup's destination-keyed ceiling, which had this and
   * the portal did not, despite the portal being the other unauthenticated door into a
   * dead person's estate. Limits are looser here because portal sign-in is a legitimately
   * repeated action across the 90-day retrieval window, where a lookup happens once.
   *
   * Suppression is SILENT: start() always answers `{ sent: true }`, and saying "rate
   * limited" would confirm the address is on the roster — the exact oracle the constant
   * response exists to close.
   */
  private async mayIssuePortalCode(destination: string): Promise<boolean> {
    // Hashed, like the lookup's: these keys live in a cache with a different blast radius
    // from the database, and a phone number is PII wherever it lands.
    const dest = hashClaimToken(destination).slice(0, 32);
    const checks: [string, number, number][] = [
      [`portal:start:dest:${dest}:h`, 60 * 60, PORTAL_START_LIMITS.perDestinationPerHour],
      [`portal:start:dest:${dest}:d`, 24 * 60 * 60, PORTAL_START_LIMITS.perDestinationPerDay],
    ];
    try {
      for (const [key, ttl, limit] of checks) {
        const count = await this.redis.incrWithTtl(key, ttl);
        if (count > limit) {
          this.logger.warn(`Portal sign-in limit hit on ${key} (${count} > ${limit}); no code sent.`);
          return false;
        }
      }
      return true;
    } catch (e) {
      // Fails CLOSED, matching the claim lookup: this is the only limit an IP-rotating
      // attacker cannot shed, so an unavailable counter must not quietly become no counter.
      // The cost is real and worth stating — while Redis is down no heir can start a portal
      // session, and because the response is constant they are told a code was sent. That is
      // a cache outage degrading into a sign-in outage, and it is the deliberate trade.
      this.logger.error(
        `Portal sign-in rate limiting is unavailable (${(e as Error).message}); refusing to send.`,
      );
      return false;
    }
  }

  /**
   * Exchanges the code for an opaque PORTAL_READ session token.
   *
   * Every failure path throws the SAME message — see PORTAL_OTP_ERROR_MESSAGE.
   */
  async verify(
    role: PortalRole,
    email: string,
    code: string,
  ): Promise<{
    token: string;
    expiresAt: Date;
    role: PortalRole;
    estateName: string;
    claimStatus: DeathClaimStatus;
  }> {
    const party = await this.resolveParty(role, email);
    const destination = party?.phone ? normalizePhone(party.phone) : (party?.email ?? '');
    // An unknown party fails exactly like a wrong code. Note this is checked BEFORE any
    // OTP work, so there is nothing to distinguish by content — the timing difference is
    // acknowledged and is not the channel this constant is defending.
    if (!party || !destination) throw new BadRequestException(PORTAL_OTP_ERROR_MESSAGE);

    let ok = false;
    try {
      ok = await this.otp.verify(destination, PORTAL_OTP_PURPOSE, code);
    } catch (e) {
      // The three distinguishable OtpService messages die here.
      if (e instanceof BadRequestException) throw new BadRequestException(PORTAL_OTP_ERROR_MESSAGE);
      throw e;
    }
    if (!ok) throw new BadRequestException(PORTAL_OTP_ERROR_MESSAGE);

    const rawToken = generateClaimToken();
    const ttlHours = Number(this.config.get('PORTAL_TOKEN_TTL_HOURS') ?? DEFAULT_PORTAL_TOKEN_TTL_HOURS);
    const expiresAt = new Date(Date.now() + ttlHours * 60 * 60 * 1000);

    await this.prisma.claimAccessToken.create({
      data: {
        // Only the hash is stored. The raw value is returned once, below, and is
        // unrecoverable from the database afterwards.
        tokenHash: hashClaimToken(rawToken),
        willId: party.willId,
        claimId: party.claimId,
        role: role as ClaimRole,
        scope: ClaimTokenScope.PORTAL_READ,
        // The identity is the ROSTER's, not the form's.
        subjectPhone: party.phone ? normalizePhone(party.phone) : '',
        subjectEmail: party.email,
        heirContactId: role === ClaimRole.HEIR ? party.partyId : null,
        expiresAt,
      },
    });

    return {
      token: rawToken,
      expiresAt,
      role,
      estateName: party.estateName,
      claimStatus: party.claimStatus,
    };
  }

  /**
   * The claim this (role, email) session should bind to, chosen by HOW MUCH the portal
   * can do with it — never by raw recency across the whole table.
   *
   * The old query was `findFirst` ordered by `createdAt desc` with no status filter and
   * no scoping beyond "some claim on some will whose roster has this email". Two real
   * failures fell out of that:
   *
   *   - DUPLICATE CLAIM DEADLOCK. A claim reaches APPROVED and the heirs start
   *     confirming; someone taps a second lookup link and files a duplicate claim on the
   *     SAME will. The duplicate is newer, so every heir session now binds to the
   *     SUBMITTED duplicate — confirm() refuses (not APPROVED), the roll-call can never
   *     complete, and release deadlocks on the very people trying to allow it.
   *   - CROSS-ESTATE ECLIPSE. An heir named on two estates got whichever estate's claim
   *     was filed LAST, regardless of state. A newly-filed claim on estate B eclipsed
   *     the RELEASED estate A until A's 90-day purge destroyed it unread.
   *
   * Selection is now by status priority, then recency within a status:
   *   APPROVED first (the portal has WORK here — the heir roll-call gates release),
   *   then RELEASED (a readable estate, purge clock ticking),
   *   then UNDER_REVIEW / SUBMITTED (status screen only),
   *   then REJECTED last (only shown when nothing live exists anywhere).
   *
   * KNOWN LIMIT, stated: one (role, email) session still binds to ONE claim. A party on
   * two estates in the SAME bucket (e.g. both RELEASED) still sees only the more recent
   * one; a real fix is an estate picker on the sign-in, which changes the public surface
   * and is a product decision, not a bug fix.
   */
  private async resolveParty(role: PortalRole, email: string): Promise<ResolvedPortalParty | null> {
    const needle = email?.trim();
    if (!needle) return null;

    const where =
      role === ClaimRole.HEIR
        ? { will: { heirContacts: { some: { email: { equals: needle, mode: 'insensitive' as const } } } } }
        : { will: { trustees: { some: { email: { equals: needle, mode: 'insensitive' as const } } } } };

    const claims = await this.prisma.deathClaim.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      include: {
        will: {
          include: {
            owner: { select: { email: true } },
            heirContacts: { select: { id: true, phone: true, email: true } },
            trustees: { select: { id: true, phone: true, email: true } },
          },
        },
      },
    });

    const ranked = [...claims].sort(
      (a, b) => PORTAL_CLAIM_PRIORITY[a.status] - PORTAL_CLAIM_PRIORITY[b.status],
    );

    for (const claim of ranked) {
      // Re-match in JS: the SQL `some` proved SOME row matches, not WHICH one. A claim
      // whose roster no longer yields a concrete party is SKIPPED, not fatal — the next
      // candidate may still be this person's estate.
      const roster = role === ClaimRole.HEIR ? claim.will.heirContacts : claim.will.trustees;
      const party = roster.find((p) => emailsMatch(p.email, needle));
      if (!party) continue;

      return {
        claimId: claim.id,
        claimStatus: claim.status,
        willId: claim.willId,
        // The User model carries no name, so the deceased's email is the only human
        // handle there is. It is already what every release notice in the product says.
        estateName: claim.will.owner.email,
        partyId: party.id,
        phone: party.phone ?? null,
        email: party.email ?? null,
      };
    }
    return null;
  }

  // --- Session-scoped reads ---------------------------------------------------

  /** Who this session is and what state the claim is in. Not gated: the prototype's
   * "Claim under review" screen is reached with exactly this. */
  async me(ctx: ClaimTokenContext) {
    const { will, claim } = await this.load(ctx);
    // A trustee who never accepted the role can sign in but cannot read the estate or
    // override the heirs. Surfaced HERE so the client can offer the one action that fixes
    // it, instead of letting them walk into a refusal on the will screen with nowhere to go.
    const trusteeAcceptancePending =
      ctx.role === ClaimRole.TRUSTEE && (await this.trusteeIdFor(ctx)).status !== TrusteeStatus.CONFIRMED;
    return {
      role: ctx.role,
      estateName: will.owner.email,
      claimStatus: claim?.status ?? null,
      trusteeAcceptancePending,
      readOnly: true as const,
    };
  }

  /**
   * Accept the trusteeship from inside the portal.
   *
   * Without this, requiring CONFIRMED to read the estate would be a trap rather than a
   * control. The release notice sends a trustee to /portal, and the ONLY other way to
   * become CONFIRMED is the /trustee/:id link from the original invitation — a uuid mailed
   * out when the will was written, possibly years earlier and long deleted. A trustee who
   * arrived to do their job would be refused with no route forward from where they stand.
   *
   * The portal session IS the proof, and it is the same proof TrusteesService.confirm asks
   * for: Trustee.phone is NOT NULL and start() prefers the phone, so the code that opened
   * this session went to the same number by the same channel. Requiring a second code from
   * a link they no longer have would add ceremony, not assurance.
   *
   * Idempotent, and conditional on the row still being PENDING so a re-tap cannot rewrite
   * the timestamp that recorded when they actually accepted.
   */
  async confirmTrusteeship(ctx: ClaimTokenContext, meta: PortalRequestMeta) {
    if (ctx.role !== ClaimRole.TRUSTEE) {
      throw new ForbiddenException('Only a trustee can accept a trusteeship.');
    }
    const trustee = await this.trusteeIdFor(ctx);
    if (trustee.status === TrusteeStatus.CONFIRMED) {
      return { confirmed: true as const };
    }
    await this.prisma.trustee.updateMany({
      where: { id: trustee.id, status: TrusteeStatus.PENDING },
      data: {
        status: TrusteeStatus.CONFIRMED,
        confirmedAt: new Date(),
        // Captured for the completion certificate, exactly as TrusteesService.confirm does.
        ipAddress: meta.ipAddress,
        userAgent: meta.userAgent,
      },
    });
    await this.logPortal(ctx, meta, 'portal.trustee.accepted', 'Trustee', trustee.id, {});
    return { confirmed: true as const };
  }

  /**
   * Reading a dead person's estate requires having ACCEPTED the trusteeship, not merely
   * having been named to it. The testator's nomination is one half; the person's own answer
   * — a code entered at their own phone — is the other, and it is what the will's completion
   * certificate records.
   *
   * Heirs are untouched: an heir is a beneficiary by the terms of the will, with nothing to
   * accept. Only the trustee role has a two-sided appointment.
   */
  private async assertTrusteeAccepted(ctx: ClaimTokenContext) {
    if (ctx.role !== ClaimRole.TRUSTEE) return;
    const trustee = await this.trusteeIdFor(ctx);
    if (trustee.status !== TrusteeStatus.CONFIRMED) {
      throw new ForbiddenException(
        'Accept your trusteeship to open this estate. You can do that from this page — it takes one tap.',
      );
    }
  }

  /**
   * The claim's state, and — once APPROVED — the heir-confirmation roll-call that gates
   * release. This is the ONLY endpoint that reveals status; see PORTAL_NOT_RELEASED_MESSAGE.
   */
  async claim(ctx: ClaimTokenContext) {
    const { claim } = await this.load(ctx);
    if (!claim) throw new NotFoundException('This claim is no longer available.');
    if (claim.status !== DeathClaimStatus.APPROVED) {
      return { status: claim.status };
    }

    const [heirs, confirmations] = await Promise.all([
      this.prisma.willHeirContact.findMany({
        where: { willId: ctx.willId },
        select: { id: true, name: true, relation: true, phone: true, email: true, isMinor: true },
        orderBy: { createdAt: 'asc' },
      }),
      this.prisma.heirReleaseConfirmation.findMany({
        where: { claimId: claim.id },
        select: { heirContactId: true, confirmedAt: true },
      }),
    ]);
    const confirmedAt = new Map(confirmations.map((c) => [c.heirContactId, c.confirmedAt]));

    return {
      status: claim.status,
      overrideActive: claim.trusteeOverrideAt != null,
      // Whether THIS heir still owes a confirmation. Always false for a trustee, who has
      // no confirmation to give.
      myConfirmationPending:
        ctx.role === ClaimRole.HEIR && ctx.heirContactId != null && !confirmedAt.has(ctx.heirContactId),
      heirConfirmations: heirs.map((h) => ({
        heirContactId: h.id,
        name: h.name,
        relation: h.relation,
        // Mirrors the release gate exactly (DeathClaimsService.reachableHeirs): a minor,
        // or an heir with no contact details at all, is not waited on.
        reachable: !h.isMinor && Boolean(h.phone || h.email),
        confirmed: confirmedAt.has(h.id),
        confirmedAt: confirmedAt.get(h.id) ?? null,
      })),
    };
  }

  /**
   * An heir records that they are ready for the will to be released. Idempotent — the
   * @@unique([claimId, heirContactId]) makes a second tap a no-op rather than a duplicate.
   */
  async confirm(ctx: ClaimTokenContext, meta: PortalRequestMeta) {
    if (ctx.role !== ClaimRole.HEIR || !ctx.heirContactId) {
      throw new ForbiddenException('Only an heir named on this will can confirm the release.');
    }
    const { claim } = await this.load(ctx);
    if (!claim || claim.status !== DeathClaimStatus.APPROVED) {
      throw new BadRequestException('This claim is not awaiting heir confirmation.');
    }

    const confirmation = await this.prisma.heirReleaseConfirmation.upsert({
      where: { claimId_heirContactId: { claimId: claim.id, heirContactId: ctx.heirContactId } },
      // A re-tap must not rewrite the original timestamp/IP: the first confirmation is the
      // evidentiary one.
      update: {},
      create: {
        claimId: claim.id,
        heirContactId: ctx.heirContactId,
        ipAddress: meta.ipAddress,
        userAgent: meta.userAgent,
      },
    });

    await this.logPortal(ctx, meta, 'portal.heir.confirm_release', 'DeathClaim', claim.id);
    return { confirmed: true as const, confirmedAt: confirmation.confirmedAt };
  }

  /**
   * The trustee forces release through without the full heir roll-call. Recorded, never
   * silent — the prototype's copy is explicit that the panel shows who overrode and when.
   */
  async override(ctx: ClaimTokenContext, meta: PortalRequestMeta) {
    if (ctx.role !== ClaimRole.TRUSTEE) {
      throw new ForbiddenException('Only the trustee can override the heir confirmations.');
    }
    const { claim } = await this.load(ctx);
    if (!claim || claim.status !== DeathClaimStatus.APPROVED) {
      throw new BadRequestException('This claim is not awaiting heir confirmation.');
    }

    const trustee = await this.trusteeIdFor(ctx);

    // The override must come from a trustee who ACCEPTED the role, not merely one who was
    // named. Being on the roster is the testator's nomination; CONFIRMED is the person's
    // own answer to it, given by entering a code sent to their phone.
    //
    // Nothing checked this. resolveParty matched trustees on email alone, the roster select
    // omitted `status`, and override() tested only ctx.role — so a trustee left PENDING for
    // years, who never responded to the invitation and has never touched Wasiati, could
    // clear the heir-confirmation gate. That gate is the product's promise that the estate
    // is released "once every registered heir confirms — or the trustee overrides": it is
    // the heirs' only say, and it could be removed by someone with no standing.
    //
    // The rest of the codebase already says this is wrong. schema.prisma:606 documents the
    // field as "A CONFIRMED trustee can override", and release() itself refuses unless
    // `trustees.filter(t => t.status === 'CONFIRMED').length > 0`. This closes the gap
    // between the two — and note the sibling gate does not cover it, because a DIFFERENT
    // trustee being confirmed satisfies release() while this one overrides.
    if (trustee.status !== TrusteeStatus.CONFIRMED) {
      throw new ForbiddenException(
        'Confirm your trusteeship before overriding the heirs. Open your trustee link and enter the code sent to your phone.',
      );
    }

    // Conditional write: only an APPROVED claim that has not already been overridden gets
    // a stamp, so the FIRST trustee to override is the one recorded and a second tap
    // cannot rewrite the attribution.
    await this.prisma.deathClaim.updateMany({
      where: { id: claim.id, status: DeathClaimStatus.APPROVED, trusteeOverrideAt: null },
      data: { trusteeOverrideAt: new Date(), trusteeOverrideBy: trustee.id },
    });

    await this.logPortal(ctx, meta, 'portal.trustee.override_release', 'DeathClaim', claim.id, {
      trusteeId: trustee.id,
    });
    const after = await this.prisma.deathClaim.findUnique({
      where: { id: claim.id },
      select: { trusteeOverrideAt: true, trusteeOverrideBy: true },
    });
    return { overrideActive: true as const, trusteeOverrideAt: after?.trusteeOverrideAt ?? null };
  }

  /**
   * The will itself. CONTENT — gated by assertReleased.
   *
   * THE WHOLE ESTATE the heirs are entitled to, not a teaser: personal message, fara'id
   * shares, bequests, the asset inventory (with the institution contacts and account
   * references the testator recorded precisely so their heirs could find each asset),
   * funeral wishes and the guardianship of minor children. Everything the deceased spent
   * their subscription recording is destroyed unread at the 90-day purge if it is not
   * handed over HERE — this payload used to carry only the message, shares and bequests,
   * so most of the estate died with the purge clock. The vault alone stays out: see the
   * class comment (DECISIONS §19).
   */
  async will(ctx: ClaimTokenContext, meta: PortalRequestMeta) {
    const { will, claim } = await this.load(ctx);
    this.assertReleased(claim);
    await this.assertTrusteeAccepted(ctx);

    const [shares, bequests, assets] = await Promise.all([
      this.prisma.shariaShare.findMany({
        where: { willId: will.id },
        select: { heirName: true, heirRelation: true, sharePercent: true },
        orderBy: { createdAt: 'asc' },
      }),
      this.prisma.bequest.findMany({
        where: { willId: will.id },
        select: { beneficiaryName: true, sharePercent: true, notes: true },
        orderBy: { createdAt: 'asc' },
      }),
      this.prisma.asset.findMany({
        where: { willId: will.id },
        orderBy: { createdAt: 'asc' },
      }),
    ]);

    await this.logPortal(ctx, meta, 'portal.will.read', 'Will', will.id);

    return {
      estateName: will.owner.email,
      personalMessage: will.personalMessage,
      // Decimal → number at the edge, so the client is never handed a Prisma Decimal's
      // string form and left to guess.
      shariaShares: shares.map((s) => ({
        heirName: s.heirName,
        heirRelation: s.heirRelation,
        sharePercent: Number(s.sharePercent),
      })),
      bequests: bequests.map((b) => ({
        beneficiaryName: b.beneficiaryName,
        sharePercent: Number(b.sharePercent),
        notes: b.notes,
      })),
      // The inventory, complete. `accountRef` is deliberately UNMASKED here: the owner's
      // UI masks it to last-4 because the owner already knows their own IBAN, but this
      // payload exists so the heirs can walk into the institution and locate the asset —
      // a masked reference would defeat the reason the field was recorded. LIABILITY-type
      // rows are debts and are included: settling them precedes the fara'id split.
      assets: assets.map((a) => ({
        type: a.type,
        label: a.label,
        institution: a.institution,
        estimatedValue: a.estimatedValue != null ? Number(a.estimatedValue) : null,
        currency: a.currency,
        notes: a.notes,
        contactPhone: a.contactPhone,
        contactEmail: a.contactEmail,
        accountRef: a.accountRef,
      })),
      // Stored as `wishes{sunnah,simple,local,azaa}` (spec §8); passed through as-is.
      funeralWishes: will.funeralWishes,
      guardianship:
        will.guardianMode == null
          ? null
          : {
              mode: will.guardianMode,
              name: will.guardianName,
              phone: will.guardianPhone,
              email: will.guardianEmail,
            },
    };
  }

  /**
   * Short-lived inline URLs for ALL of the deceased's legacy videos. CONTENT — gated.
   *
   * ALL of them, oldest first, because the singular predecessor served only the most
   * recent upload: a testator who recorded one message per child would have had every
   * video but the last silently withheld and then purged at day 90.
   *
   * Goes through FilesService.presignDownloadForRelease, a SECOND named entry point
   * alongside presignDownloadOwned. Deliberately not a loosening of the owner-facing one:
   * "this file belongs to the caller" and "this file belongs to an estate the caller has
   * been released" are different claims and must be different doors, so a reader can see
   * at a glance which callers reach a dead person's files.
   *
   * An estate with no videos is `{ videos: [] }`, not a 404 — the caller is already past
   * the release gate, so there is nothing to hide and nothing exceptional about a
   * testator who never recorded one.
   */
  async videos(ctx: ClaimTokenContext, meta: PortalRequestMeta) {
    const { will, claim } = await this.load(ctx);
    this.assertReleased(claim);
    await this.assertTrusteeAccepted(ctx);

    // Files are owner-scoped, not will-scoped (FileObject has no willId): every legacy
    // video the deceased uploaded belongs to the estate being handed over.
    const rows = await this.prisma.fileObject.findMany({
      where: { userId: will.ownerId, kind: 'video_legacy' },
      orderBy: { createdAt: 'asc' },
    });

    const videos = [];
    for (const row of rows) {
      const { url } = await this.files.presignDownloadForRelease(will.ownerId, row.id);
      videos.push({
        fileId: row.id,
        url,
        contentType: row.contentType,
        sizeBytes: row.sizeBytes,
        recordedAt: row.createdAt,
      });
    }

    await this.logPortal(ctx, meta, 'portal.videos.read', 'Will', will.id, {
      fileIds: rows.map((r) => r.id),
      count: rows.length,
    });
    return { videos };
  }

  /**
   * The executed will as a print-ready PDF. CONTENT — gated by assertReleased.
   *
   * Rendered by the SAME WillDocumentService the owner's export uses, so what the heirs
   * receive is byte-for-byte the document the testator proofread — a second renderer here
   * would inevitably drift. The owner route's export gate (witnesses signed + trustee
   * confirmed) is not re-checked because release() already enforces strictly more: a
   * claim only reaches RELEASED on a SEALED will with a CONFIRMED trustee.
   */
  async pdf(ctx: ClaimTokenContext, meta: PortalRequestMeta, opts: WillDocumentOptions = {}): Promise<Buffer> {
    const { will, claim } = await this.load(ctx);
    this.assertReleased(claim);
    // The PDF is the whole estate in one file — the LAST place to leave ungated.
    await this.assertTrusteeAccepted(ctx);

    const [shares, bequests, witnesses, trustees, assets] = await Promise.all([
      this.prisma.shariaShare.findMany({ where: { willId: will.id }, orderBy: { createdAt: 'asc' } }),
      this.prisma.bequest.findMany({ where: { willId: will.id }, orderBy: { createdAt: 'asc' } }),
      this.prisma.witness.findMany({ where: { willId: will.id }, orderBy: { createdAt: 'asc' } }),
      this.prisma.trustee.findMany({ where: { willId: will.id }, orderBy: { createdAt: 'asc' } }),
      this.prisma.asset.findMany({ where: { willId: will.id }, orderBy: { createdAt: 'asc' } }),
    ]);

    const rendered = await this.documents.renderPdf(
      {
        ...will,
        ownerEmail: will.owner.email,
        shariaShares: shares,
        bequests,
        witnesses,
        trustees,
        assets: assets.map((a) => ({
          type: a.type,
          label: a.label,
          institution: a.institution,
          estimatedValue: a.estimatedValue,
          currency: a.currency,
        })),
      },
      opts,
    );

    await this.logPortal(ctx, meta, 'portal.will.pdf', 'Will', will.id);
    return rendered;
  }

  /**
   * Ends the session by burning the token. The guard refuses a consumed token, so this is a
   * real revocation and not a client-side forget — it matters because the credential is a
   * bearer string that may be sitting in a shared family device's browser.
   */
  async exit(ctx: ClaimTokenContext) {
    await this.prisma.claimAccessToken.updateMany({
      where: { id: ctx.tokenId, consumedAt: null },
      data: { consumedAt: new Date() },
    });
    return { signedOut: true as const };
  }

  // --- Internals --------------------------------------------------------------

  /** The estate and claim this token speaks for. willId ALWAYS comes off the token. */
  private async load(ctx: ClaimTokenContext) {
    const will = await this.prisma.will.findUnique({
      where: { id: ctx.willId },
      include: { owner: { select: { id: true, email: true } } },
    });
    if (!will) throw new NotFoundException('This estate is no longer available.');
    const claim = ctx.claimId
      ? await this.prisma.deathClaim.findUnique({ where: { id: ctx.claimId } })
      : null;
    return { will, claim };
  }

  /**
   * The single content gate. ONE message for all four non-released statuses AND for a claim
   * that has disappeared — see PORTAL_NOT_RELEASED_MESSAGE for why that has to hold.
   */
  private assertReleased(claim: { status: DeathClaimStatus } | null): void {
    if (!claim || claim.status !== DeathClaimStatus.RELEASED) {
      throw new ForbiddenException(PORTAL_NOT_RELEASED_MESSAGE);
    }
  }

  /**
   * Which Trustee row this token speaks for.
   *
   * ClaimTokenContext carries no trustee id (it has heirContactId only), so the subject is
   * re-read from the token ROW and matched against the will's roster — the same extra read
   * submitClaim does, for the same reason. Matching on the token's subject rather than
   * anything in the request is what keeps the attribution honest.
   */
  private async trusteeIdFor(ctx: ClaimTokenContext): Promise<{ id: string; status: TrusteeStatus }> {
    const token = await this.prisma.claimAccessToken.findUnique({
      where: { id: ctx.tokenId },
      select: { subjectEmail: true, subjectPhone: true },
    });
    const trustees = await this.prisma.trustee.findMany({
      where: { willId: ctx.willId },
      // status is SELECTED, and that is the point: without it the override could be — and
      // was — exercised by a trustee who never accepted the role. See override().
      select: { id: true, phone: true, email: true, status: true },
    });
    const match = trustees.find(
      (t) => emailsMatch(t.email, token?.subjectEmail) || phonesMatch(t.phone, token?.subjectPhone),
    );
    if (!match) {
      // The roster changed under a live session. Refuse rather than stamping an override
      // that no trustee row can be held to.
      throw new ForbiddenException('You are no longer listed as the trustee on this will.');
    }
    return { id: match.id, status: match.status };
  }

  /**
   * One audit row per portal action. Reading a dead person's estate must be auditable — the
   * prototype promises "Document access is logged to the audit trail".
   *
   * NEVER the raw token and never a full phone number or address (NotificationsService's
   * house style). `actorId` stays UNSET: the column means "user id" everywhere else in the
   * trail and a portal holder has no User row, so writing a roster id into it would make
   * the actorId index mean two different things depending on the source. The party id lives
   * in metadata, where it cannot be mistaken for a user.
   */
  private async logPortal(
    ctx: ClaimTokenContext,
    meta: PortalRequestMeta,
    action: string,
    targetType: string,
    targetId: string,
    extra?: Record<string, unknown>,
  ): Promise<void> {
    const token = await this.prisma.claimAccessToken
      .findUnique({ where: { id: ctx.tokenId }, select: { subjectEmail: true, subjectPhone: true } })
      .catch(() => null);
    await this.audit.log({
      actorRole: `PORTAL_${ctx.role}`,
      action,
      targetType,
      targetId,
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
      metadata: {
        willId: ctx.willId,
        claimId: ctx.claimId,
        tokenId: ctx.tokenId,
        heirContactId: ctx.heirContactId,
        subject: maskContact(token?.subjectEmail ?? token?.subjectPhone),
        ...extra,
      },
    });
  }
}
