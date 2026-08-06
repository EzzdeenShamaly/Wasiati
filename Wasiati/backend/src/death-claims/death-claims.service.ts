import { Injectable, BadRequestException, ConflictException, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { appBaseUrl } from '../common/app-url';
import { ClaimInitPolicy, ClaimRole, ClaimTokenScope } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { OtpService } from '../auth/otp.service';
import { DataRetentionService } from '../data-retention/data-retention.service';
import { randomBytes } from 'crypto';
import { RedisService } from '../redis/redis.service';
import { FilesService } from '../files/files.service';
import { ClaimTokenContext, hashClaimToken } from './claim-token.guard';
import { normalizePhone, phoneLookupVariants, phonesMatch } from '../common/phone.util';

/**
 * Mints a raw, opaque claim token. Returned ONCE, delivered out-of-band in a link, and
 * never stored — only `hashClaimToken(raw)` is persisted, which is what makes the
 * `tokenHash @unique` column a single indexed lookup for the guard.
 *
 * 256 bits from a CSPRNG: this is a bearer credential to a dead person's estate, so the
 * search space has to be unreachable rather than merely slow. base64url so it survives a
 * URL path segment untouched — a token needing percent-encoding gets mangled by one mail
 * client in ten and the family sees a dead link with no way to tell why.
 */
export function generateClaimToken(): string {
  return randomBytes(32).toString('base64url');
}

/** A party the testator attached to the will, matched against a contact someone typed. */
export interface AuthorizedParty {
  role: ClaimRole;
  /** Witness.id | Trustee.id | WillHeirContact.id — which row matched. */
  partyId: string;
  phone?: string;
  email?: string;
}

/** The minimum a will must carry for `authorizedParties` to judge it. */
export interface WillParties {
  witnesses: { id: string; phone: string; email: string | null }[];
  trustees: { id: string; phone: string; email: string | null }[];
  heirContacts: { id: string; phone: string | null; email: string | null }[];
  owner: { claimInitPolicy: ClaimInitPolicy };
}

/** How long a minted claim-submit link stays usable. */
const DEFAULT_CLAIM_TOKEN_TTL_HOURS = 168; // 7 days

/**
 * How long a DECIDED claim (REJECTED / RELEASED) stays on the admin queue after its
 * decision. Long enough to review a recent decision on the same screen the prototype
 * designs; short enough that the queue never becomes the full history.
 */
export const DECIDED_CLAIM_QUEUE_DAYS = 30;

/** Abuse ceilings enforced in the SERVICE, so rotating IPs cannot shed them. */
const LOOKUP_LIMITS = {
  /** Invitations minted for one will per rolling day. */
  perWillPerDay: 3,
  /** Messages sent to one destination per hour, and per day. */
  perDestinationPerHour: 3,
  perDestinationPerDay: 10,
};

@Injectable()
export class DeathClaimsService {
  private readonly logger = new Logger(DeathClaimsService.name);

  constructor(
    private prisma: PrismaService,
    private notifications: NotificationsService,
    private otp: OtpService,
    private retention: DataRetentionService,
    private config: ConfigService,
    private redis: RedisService,
    private files: FilesService,
  ) {}

  /**
   * Who may initiate a death claim, per the testator's chosen policy (spec §6):
   *   TRUSTEE_ONLY         — only the trustee.
   *   HEIRS_WITH_DOCUMENTS — an heir, or a witness (who must still upload a certificate).
   *   BOTH                 — any of the three.
   * A death certificate and a human review are required in every case regardless.
   *
   * HEIRS_WITH_DOCUMENTS used to mean `role === 'WITNESS'` — not because the policy is
   * about witnesses, but because there was no heir roster to match against, so witnesses
   * stood in for heirs. `will.heirContacts` exists now (and is documented as existing
   * "so the will can be released to each at claim time"), so the policy finally means what
   * its name says. Witnesses stay eligible: they were the only people this policy ever
   * admitted, and dropping them would silently lock out every will already relying on it.
   */
  static policyAllows(policy: ClaimInitPolicy, role: ClaimRole): boolean {
    switch (policy) {
      case ClaimInitPolicy.TRUSTEE_ONLY:
        return role === ClaimRole.TRUSTEE;
      case ClaimInitPolicy.HEIRS_WITH_DOCUMENTS:
        return role === ClaimRole.WITNESS || role === ClaimRole.HEIR;
      case ClaimInitPolicy.BOTH:
        return true;
    }
  }

  /** Case-insensitive email comparison; blank never matches blank. */
  private static emailsMatch(a?: string | null, b?: string | null): boolean {
    if (!a || !b) return false;
    return a.trim().toLowerCase() === b.trim().toLowerCase();
  }

  /** True when `contact` is the same phone OR the same email as the party's. */
  private static contactMatches(contact: string, phone?: string | null, email?: string | null): boolean {
    return phonesMatch(contact, phone) || DeathClaimsService.emailsMatch(contact, email);
  }

  /**
   * Every party on this will that `contact` identifies, filtered by the testator's
   * policy. Replaces `authorizedRole`, which returned at most one role and searched only
   * witnesses and trustees on phone alone.
   *
   * Matches on BOTH phone and email because the roster stores both and a family member
   * reaching for the one flow that gets them in should not have to guess which of the two
   * the deceased happened to record.
   *
   * A party excluded by the policy is dropped here, so it is indistinguishable from a
   * stranger and the policy itself cannot be probed by trying contacts.
   */
  static authorizedParties(will: WillParties, contact: string): AuthorizedParty[] {
    if (!contact?.trim()) return [];
    const parties: AuthorizedParty[] = [];

    for (const w of will.witnesses) {
      if (DeathClaimsService.contactMatches(contact, w.phone, w.email)) {
        parties.push({ role: ClaimRole.WITNESS, partyId: w.id, phone: w.phone, email: w.email ?? undefined });
      }
    }
    for (const t of will.trustees) {
      if (DeathClaimsService.contactMatches(contact, t.phone, t.email)) {
        parties.push({ role: ClaimRole.TRUSTEE, partyId: t.id, phone: t.phone, email: t.email ?? undefined });
      }
    }
    for (const h of will.heirContacts) {
      if (DeathClaimsService.contactMatches(contact, h.phone, h.email)) {
        parties.push({
          role: ClaimRole.HEIR,
          partyId: h.id,
          phone: h.phone ?? undefined,
          email: h.email ?? undefined,
        });
      }
    }

    return parties.filter((p) => DeathClaimsService.policyAllows(will.owner.claimInitPolicy, p.role));
  }

  // --- The way in: lookup -----------------------------------------------------

  /** Prisma select shared by the lookup and the party matcher. */
  private static readonly PARTIES_SELECT = {
    id: true,
    witnesses: { select: { id: true, phone: true, email: true } },
    trustees: { select: { id: true, phone: true, email: true } },
    heirContacts: { select: { id: true, phone: true, email: true } },
    owner: { select: { claimInitPolicy: true } },
  } as const;

  /**
   * THE way in. A family member has no account, no willId and no link — they have the
   * deceased's contact details and their own.
   *
   * ALWAYS 202 `{ acknowledged: true }`, byte-identical, in every case: no such person,
   * person with no sealed will, person found but caller not on it, and full match. The
   * response is not a channel. Only the last case mints anything, and the link goes to the
   * contact ALREADY ON FILE for the matched party — never to whatever was typed into the
   * form, which is what stops a stranger redirecting a family's claim link to themselves.
   *
   * WHY TWO FIELDS. With one (just the deceased), a single request against a guessed email
   * fans SMS out to every witness, trustee and heir on that will: a harassment amplifier
   * that simultaneously leaks "this person is claimable" to anyone who can type an address.
   * Requiring the claimant's own contact means an attacker must ALREADY know both sides of
   * the pair, and even then can only pester the one party they named — capped by the
   * per-destination counter below.
   *
   * This method does not throw. An exception escaping here would become a 500, and a 500
   * on one input and a 202 on another is precisely the oracle the constant response exists
   * to close.
   */
  async lookup(deceasedContact: string, claimantContact: string): Promise<{ acknowledged: true }> {
    try {
      await this.resolveAndInvite(deceasedContact, claimantContact);
    } catch (e) {
      // Log it, never surface it. A failure here must look exactly like a miss.
      this.logger.error(`Claim lookup failed internally: ${(e as Error).message}`);
    }
    return { acknowledged: true };
  }

  /**
   * The body of `lookup`. Separated so `lookup` has exactly one exit and cannot grow a
   * branch that returns something else.
   */
  private async resolveAndInvite(deceasedContact: string, claimantContact: string): Promise<void> {
    const deceased = await this.resolveDeceased(deceasedContact);
    if (!deceased) return this.dummyWork();

    // SEALED only. A draft or unsealed will is not a will yet, and admitting one would
    // let the lookup confirm the existence of an account that has never published
    // anything — the widest version of the "is this person claimable" leak.
    const wills = await this.prisma.will.findMany({
      where: { ownerId: deceased.id, status: 'SEALED' },
      select: DeathClaimsService.PARTIES_SELECT,
      orderBy: { sealedAt: 'desc' },
    });
    if (wills.length === 0) return this.dummyWork();

    for (const will of wills) {
      const [party] = DeathClaimsService.authorizedParties(will as unknown as WillParties, claimantContact);
      if (!party) continue;
      await this.mintAndDeliver(will.id, party);
      return; // one invitation per lookup, to the one party the caller named
    }

    return this.dummyWork();
  }

  /**
   * Resolves the deceased's contact to a user. Email is an indexed, case-insensitive
   * equality; phone goes through `phoneLookupVariants` (an indexed `IN`) and is then
   * re-checked with `phonesMatch`, because the loose comparison cannot run in SQL.
   */
  private async resolveDeceased(contact: string): Promise<{ id: string } | null> {
    const raw = contact.trim();
    if (!raw) return null;

    if (raw.includes('@')) {
      return this.prisma.user.findFirst({
        where: { email: { equals: raw, mode: 'insensitive' } },
        select: { id: true },
      });
    }

    const variants = phoneLookupVariants(raw);
    if (variants.length === 0) return null;
    const candidates = await this.prisma.user.findMany({
      where: { phone: { in: variants } },
      select: { id: true, phone: true },
    });
    return candidates.find((c) => phonesMatch(raw, c.phone)) ?? null;
  }

  /**
   * Work done on every non-matching path so a miss costs roughly what a hit costs.
   *
   * HONEST ABOUT ITS LIMITS: this NARROWS the timing channel, it does not close it — a
   * hit still performs a write the miss does not. It buys back the largest and most
   * variable component (the SHA-256 plus an indexed token read), and the delivery itself
   * is deliberately off the response path in `mintAndDeliver` so an SMS gateway's latency
   * — by far the loudest signal available — never reaches the caller's stopwatch.
   */
  private async dummyWork(): Promise<void> {
    const hash = hashClaimToken(generateClaimToken());
    await this.prisma.claimAccessToken.findUnique({ where: { tokenHash: hash } });
  }

  /**
   * Mints a single-use CLAIM_SUBMIT token and sends the link to the party's ON-FILE
   * contact, subject to the abuse counters.
   */
  private async mintAndDeliver(willId: string, party: AuthorizedParty): Promise<void> {
    // Prefer SMS: the roster always carries a phone for witnesses and trustees, and it is
    // the channel the rest of the claim flow already uses. Heirs may have only an email.
    const destination = party.phone ? normalizePhone(party.phone) : (party.email ?? '');
    if (!destination) {
      this.logger.warn(`Claim lookup matched party ${party.partyId} on will ${willId} with no contact on file.`);
      return;
    }

    if (!(await this.withinLookupLimits(willId, destination))) return;

    const rawToken = generateClaimToken();
    const ttlHours = Number(this.config.get('CLAIM_TOKEN_TTL_HOURS') ?? DEFAULT_CLAIM_TOKEN_TTL_HOURS);
    await this.prisma.claimAccessToken.create({
      data: {
        tokenHash: hashClaimToken(rawToken),
        willId,
        role: party.role,
        scope: ClaimTokenScope.CLAIM_SUBMIT,
        // The identity the token speaks for is the roster's, not the form's.
        subjectPhone: party.phone ? normalizePhone(party.phone) : '',
        subjectEmail: party.email ?? null,
        heirContactId: party.role === ClaimRole.HEIR ? party.partyId : null,
        expiresAt: new Date(Date.now() + ttlHours * 60 * 60 * 1000),
      },
    });

    // Fire-and-forget: the token is durable, and awaiting the gateway would make a hit
    // measurably slower than a miss on the very endpoint whose whole design is that the
    // two are indistinguishable. A delivery failure is logged, not surfaced.
    void this.deliverInvite(destination, rawToken).catch((e) =>
      this.logger.error(`Could not deliver a claim invitation: ${(e as Error).message}`),
    );
  }

  /** The link the family receives. Path segment, not a query string — see the guard. */
  private inviteLink(rawToken: string): string {
    const base = appBaseUrl(this.config);
    return `${base.replace(/\/+$/, '')}/claim/${rawToken}`;
  }

  private async deliverInvite(destination: string, rawToken: string): Promise<void> {
    const link = this.inviteLink(rawToken);
    const body =
      `Wasiati: someone has asked us to begin the process of releasing a will you are named on. ` +
      `If this was you, continue here: ${link}. If it was not, you can ignore this message.`;
    if (destination.includes('@')) {
      await this.notifications.sendEmail(destination, 'Wasiati: continue a will release', body);
    } else {
      await this.notifications.sendSms(destination, body);
    }
  }

  /**
   * Per-will and per-destination ceilings, counted in Redis rather than by the per-IP
   * throttler. The throttler is the first line and stops the naive case, but an attacker
   * with a proxy pool rotates straight past it — these counters key off the WILL and the
   * DESTINATION, neither of which the caller can rotate.
   *
   * FAILS CLOSED. If Redis is unreachable we decline to send rather than waving the
   * request through: this endpoint's only abuse control that survives IP rotation is this
   * one, and an unmetered public SMS fan-out is a worse outcome than a claim that must be
   * retried after the cache comes back. Logged at error level so the outage is visible.
   */
  private async withinLookupLimits(willId: string, destination: string): Promise<boolean> {
    // Hash the destination: these keys sit in a cache with a different blast radius from
    // the database, and a phone number is PII wherever it lands.
    const dest = hashClaimToken(destination).slice(0, 32);
    const day = 24 * 60 * 60;
    const checks: [string, number, number][] = [
      [`claim:lookup:will:${willId}`, day, LOOKUP_LIMITS.perWillPerDay],
      [`claim:lookup:dest:${dest}:h`, 60 * 60, LOOKUP_LIMITS.perDestinationPerHour],
      [`claim:lookup:dest:${dest}:d`, day, LOOKUP_LIMITS.perDestinationPerDay],
    ];

    try {
      for (const [key, ttl, limit] of checks) {
        const count = await this.redis.incrWithTtl(key, ttl);
        if (count > limit) {
          this.logger.warn(`Claim-lookup limit hit on ${key} (${count} > ${limit}); no invitation sent.`);
          return false;
        }
      }
      return true;
    } catch (e) {
      this.logger.error(
        `Claim-lookup rate limiting is unavailable (${(e as Error).message}); refusing to send. ` +
          'Failing closed: this is the only limit an IP-rotating attacker cannot shed.',
      );
      return false;
    }
  }

  // --- Filing the claim -------------------------------------------------------

  /**
   * Files the claim. Everything identifying — which will, who, what role — comes from
   * the TOKEN; the body carries only what the token cannot know.
   *
   * The old route took `willId` from the path and `phone` from the body, which is what
   * made it an enumeration oracle: three different errors (unknown will / known will but
   * unauthorised phone / authorised but no pending code) told a caller exactly where they
   * had got to. That is gone structurally rather than by flattening the messages — there
   * is no longer any caller-supplied identifier to probe with.
   */
  async submitClaim(principal: ClaimTokenContext, submittedByName: string, certificateFileId: string) {
    const will = await this.prisma.will.findUnique({
      where: { id: principal.willId },
      include: { owner: true },
    });
    if (!will) throw new NotFoundException('This will is no longer available.');

    const certificate = await this.prisma.fileObject.findUnique({ where: { id: certificateFileId } });
    // The file must belong to THIS estate. Kind and scan status were checked; ownership
    // was not, so any CLEAN death_certificate id passed — including one from a different
    // estate entirely. Claim uploads are attributed to the deceased owner
    // (claim-uploads.controller.ts:113 → ownerIdOf(claim.willId)), and that attribution is
    // exactly what makes this comparison possible.
    //
    // Reachable without guessing a uuid: the upload endpoint returns the file id to
    // whoever uploaded it, so anyone who has legitimately filed on one estate holds a
    // valid id and can present that real certificate as evidence on another. The reviewer
    // then sees a genuine death certificate — for the wrong person.
    //
    // Same message as the missing-file case on purpose. "That file is not yours" would
    // confirm the id exists, turning the check into an oracle over stored objects.
    if (!certificate || certificate.kind !== 'death_certificate' || certificate.userId !== will.ownerId) {
      throw new BadRequestException('Upload the death certificate before submitting the claim.');
    }
    // Never admit an unscanned or infected file into a queue a human is about to open.
    if (certificate.scanStatus !== 'CLEAN') {
      throw new BadRequestException(
        certificate.scanStatus === 'INFECTED'
          ? 'That file did not pass our security scan. Please upload the certificate again.'
          : 'That file is still being scanned. Please try again in a moment.',
      );
    }

    // The stored URL is now DERIVED from an id we looked up, never a string the caller
    // supplied — so the reviewer-SSRF class the old `assertCertificateHost` allow-list
    // existed to mitigate is structurally impossible, and the allow-list is gone with it.
    const certificateFileUrl = this.certificateUrl(certificate.id);

    // Consume the token and file the claim together: a single-use credential that is
    // spent without producing a claim strands the family, and one that produces a claim
    // without being spent lets a shared link file the same death twice.
    const claim = await this.prisma.$transaction(async (tx) => {
      // Burn the token FIRST, with `consumedAt: null` in the WHERE so the check and the
      // write are one statement. Two taps on a link sitting in a shared family inbox
      // cannot both file the same death.
      const consumed = await tx.claimAccessToken.updateMany({
        where: { id: principal.tokenId, consumedAt: null },
        data: { consumedAt: new Date() },
      });
      if (consumed.count === 0) {
        throw new BadRequestException('This link has already been used.');
      }

      // `subjectPhone` is on the token ROW, not in ClaimTokenContext, so read it here.
      // It is the number the invitation was DELIVERED to — the only phone in this flow
      // that came off the will's roster rather than out of a form.
      const token = await tx.claimAccessToken.findUnique({
        where: { id: principal.tokenId },
        select: { subjectPhone: true },
      });

      const created = await tx.deathClaim.create({
        data: {
          willId: principal.willId,
          submittedByName,
          submittedByPhone: token?.subjectPhone ?? '',
          submittedByRole: principal.role,
          certificateFileUrl,
          // Also as an id. The URL alone was unusable by the one person who has to look
          // at this document — see certificateForReview().
          certificateFileId: certificate.id,
          status: 'SUBMITTED',
        },
      });

      // Point the spent token at what it produced, so the audit runs both ways.
      await tx.claimAccessToken.update({ where: { id: principal.tokenId }, data: { claimId: created.id } });
      return created;
    });

    await this.notifyAdmins(
      'New death claim awaiting review',
      `${submittedByName} (${principal.role}) submitted a death claim for ${will.owner.email}. Review it in the admin queue.`,
    );

    return claim;
  }

  /** Server-side download URL for a confirmed upload. */
  private certificateUrl(fileId: string): string {
    const base = appBaseUrl(this.config);
    return `${base.replace(/\/+$/, '')}/files/${fileId}/download`;
  }

  /**
   * A short-lived link to the death certificate, for the ADMIN reviewing the claim.
   *
   * Until this existed the review was performed blind. `certificateFileUrl` points at
   * `/files/:id/download`, and the only handler of that shape is owner-scoped: it loads
   * the row and refuses unless `file.userId === callerId`. Claim uploads are attributed
   * to the DECEASED owner, so there was no request any admin could make that returned
   * those bytes — while submitClaim's own comment describes the queue as one "a human is
   * about to open". Approve started the 72h window and, three days later, Release handed
   * over the estate, on a document nobody had been able to look at.
   *
   * A third named entry point rather than a relaxed general one, following
   * presignDownloadForRelease: `grep presignDownloadForClaimReview` answers "who else can
   * read a dead person's files" exactly, and widening one path cannot silently widen the
   * others. Authorization lives with the caller — the controller is @Roles('ADMIN') — and
   * this method's job is to prove the file really is THIS claim's certificate.
   */
  async certificateForReview(claimId: string): Promise<{ url: string }> {
    const claim = await this.prisma.deathClaim.findUnique({
      where: { id: claimId },
      select: { certificateFileId: true, will: { select: { ownerId: true } } },
    });
    if (!claim) throw new NotFoundException('Claim not found.');
    if (!claim.certificateFileId) {
      // Only reachable for rows written before the id was stored and whose URL did not
      // match the backfill pattern. Say so plainly: a reviewer who cannot see the
      // certificate must know that is what is happening, not be handed a broken link.
      throw new NotFoundException(
        'This claim has no resolvable certificate file — it predates certificate-file tracking. Do not approve it without obtaining the document out of band.',
      );
    }
    // Scoped to the estate this claim belongs to, so an admin cannot pass one claim's id
    // and be handed another estate's document by a mismatched row.
    return this.files.presignDownloadForClaimReview(claim.will.ownerId, claim.certificateFileId);
  }

  // --- Admin review queue -----------------------------------------------------

  /**
   * The admin claims queue: every claim that still needs an admin's attention.
   *
   * INCLUDES APPROVED. An approved claim is not done — it is waiting for the safety
   * window, the heir confirmations and the Release button, and this queue is the ONLY
   * admin surface. The old filter ({SUBMITTED, UNDER_REVIEW}) made a claim vanish the
   * moment it was approved, so the release step could never be reached in-product and
   * every "released" estate to date was released by hand in SQL or not at all.
   *
   * Decided claims (REJECTED / RELEASED) stay visible for DECIDED_CLAIM_QUEUE_DAYS and
   * then drop out: the DV2.1 prototype's admin claims screen renders a card per state —
   * pending (approve/reject), approved (heir roll-call + override + Release), rejected
   * (with its reason) and released (with "preview heir view") — so an admin must see a
   * recent decision on the same screen, but the queue must not accumulate every
   * historical claim forever.
   *
   * Each APPROVED claim carries a `releaseGate` block mirroring release()'s exact
   * preconditions, so the admin UI can enable/disable the Release button and show WHY
   * without re-deriving server rules client-side. Other statuses carry `releaseGate:
   * null`. `will.owner` is a narrow select — the old `owner: true` shipped the owner's
   * passwordHash and mfaSecret to the admin client with every queue poll.
   */
  async listPendingReview() {
    const decidedCutoff = new Date(Date.now() - DECIDED_CLAIM_QUEUE_DAYS * 24 * 60 * 60 * 1000);
    const claims = await this.prisma.deathClaim.findMany({
      where: {
        OR: [
          // Needing an action — always shown, however old.
          { status: { in: ['SUBMITTED', 'UNDER_REVIEW', 'APPROVED'] } },
          // Recently decided — shown for the window, keyed off the DECISION time
          // (not createdAt, or a slow review would expire the moment it concluded).
          { status: 'REJECTED', reviewedAt: { gte: decidedCutoff } },
          { status: 'RELEASED', releasedAt: { gte: decidedCutoff } },
        ],
      },
      include: {
        will: {
          select: {
            id: true,
            status: true,
            owner: { select: { id: true, email: true, phone: true, region: true } },
            heirContacts: { select: { id: true, name: true, relation: true, phone: true, email: true, isMinor: true } },
            trustees: { select: { status: true } },
          },
        },
        heirConfirmations: { select: { heirContactId: true, confirmedAt: true } },
      },
      orderBy: { createdAt: 'asc' },
    });

    const windowHours = Number(this.config.get('DEATH_CLAIM_SAFETY_WINDOW_HOURS') ?? 72);
    return claims.map(({ will, heirConfirmations, ...claim }) => ({
      ...claim,
      will: { id: will.id, status: will.status, owner: will.owner },
      releaseGate:
        claim.status === 'APPROVED'
          ? this.releaseGateOf(claim, will, heirConfirmations, windowHours)
          : null,
    }));
  }

  /**
   * The Release button's state, derived from the SAME preconditions release() enforces.
   * Purely informational — release() re-checks everything itself, so a stale or
   * hand-crafted client can never talk its way past the real gate.
   */
  private releaseGateOf(
    claim: { safetyCheckSentAt: Date | null; trusteeOverrideAt: Date | null },
    will: {
      status: string;
      heirContacts: { id: string; name: string; relation: string; phone: string | null; email: string | null; isMinor: boolean }[];
      trustees: { status: string }[];
    },
    heirConfirmations: { heirContactId: string; confirmedAt: Date }[],
    windowHours: number,
  ) {
    const releasableAt = claim.safetyCheckSentAt
      ? new Date(new Date(claim.safetyCheckSentAt).getTime() + windowHours * 60 * 60 * 1000)
      : null;
    const safetyWindowElapsed = releasableAt != null && releasableAt.getTime() <= Date.now();

    const confirmedAt = new Map(heirConfirmations.map((c) => [c.heirContactId, c.confirmedAt]));
    // Mirrors assertHeirGateSatisfied: a minor, or an heir with no contact at all,
    // is not waited on.
    // NO NAMES, NO RELATIONS. assertHeirGateSatisfied deliberately reports only a count
    // because "the roster of a private will is not theirs to read out of an error string" —
    // and this payload, to the same admin on the same screen, was handing over every heir's
    // name and relationship to the deceased. Either the refusal was wrong or this was; the
    // refusal is right, so this is what changes. An operator needs to know how many answers
    // are outstanding and whether the estate is releasable, not who the children are.
    const heirs = will.heirContacts.map((h) => ({
      heirContactId: h.id,
      reachable: !h.isMinor && Boolean(h.phone || h.email),
      confirmed: confirmedAt.has(h.id),
      confirmedAt: confirmedAt.get(h.id) ?? null,
    }));
    // Counted by ASKABLE PARTY, exactly as assertHeirGateSatisfied does — heirs sharing one
    // sign-in address can only be asked once, so they are one party. If this counted rows
    // instead, the panel would show an outstanding confirmation that release() considers
    // satisfied, and an admin would sit waiting for an answer that can never arrive.
    const outstanding = DeathClaimsService.askableParties(
      will.heirContacts.filter((h) => !h.isMinor && (h.phone || h.email)),
    ).filter((rows) => !rows.some((h) => confirmedAt.has(h.id))).length;
    const overrideActive = claim.trusteeOverrideAt != null;
    const heirsSatisfied = overrideActive || outstanding === 0;

    const willSealed = will.status === 'SEALED';
    const trusteeConfirmed = will.trustees.some((t) => t.status === 'CONFIRMED');

    return {
      releasableAt,
      safetyWindowElapsed,
      willSealed,
      trusteeConfirmed,
      overrideActive,
      outstandingHeirConfirmations: outstanding,
      heirs,
      heirsSatisfied,
      /** True when release() would succeed right now. */
      ready: safetyWindowElapsed && willSealed && trusteeConfirmed && heirsSatisfied,
    };
  }

  async markUnderReview(claimId: string, adminUserId: string) {
    // Atomic source-state guard: only a not-yet-decided claim can move to review, so a
    // REJECTED/RELEASED claim can't be dragged back into the queue and re-decided.
    const res = await this.prisma.deathClaim.updateMany({
      where: { id: claimId, status: { in: ['SUBMITTED', 'UNDER_REVIEW'] } },
      data: { status: 'UNDER_REVIEW', reviewedBy: adminUserId },
    });
    if (res.count === 0) {
      throw new BadRequestException('This claim is already decided and cannot be moved back to review.');
    }
    return this.prisma.deathClaim.findUnique({ where: { id: claimId } });
  }

  /**
   * Admin approves the certificate as genuine. This does NOT release the will yet — it
   * starts the cooling-off delay that `release` enforces before the irreversible handover.
   *
   * The transition is an atomic `updateMany` with the source states in the WHERE clause,
   * matching `markUnderReview` and `reject`. It used to read the claim, check the status
   * in an `if`, and then write — so two concurrent approves both read SUBMITTED, both
   * passed the check, and both wrote a fresh `safetyCheckSentAt`. The second write silently
   * restarted the 72h anti-fraud window, which is the one delay standing between a forged
   * certificate and a released estate. Now exactly one caller can win.
   */
  async approveAndSendSafetyCheck(claimId: string, adminUserId: string) {
    const claim = await this.prisma.deathClaim.findUnique({
      where: { id: claimId },
      include: { will: { include: { owner: true } } },
    });
    if (!claim) throw new NotFoundException('Claim not found.');

    const safetyCheckSentAt = new Date();
    const res = await this.prisma.deathClaim.updateMany({
      where: { id: claimId, status: { in: ['SUBMITTED', 'UNDER_REVIEW'] } },
      data: {
        status: 'APPROVED',
        safetyCheckSentAt,
        reviewedBy: adminUserId,
        reviewedAt: new Date(),
      },
    });
    if (res.count === 0) {
      throw new BadRequestException(`A ${claim.status.toLowerCase()} claim cannot be approved.`);
    }

    // AFTER the transition, never before. The ping goes to the DECEASED's number, and a
    // caller that loses the race must not fire a second one — a bereaved family being
    // texted twice by the system that is processing their death claim is its own harm,
    // and it would also hand an attacker a way to make that phone ring repeatedly.
    const ownerPhone = claim.will.owner.phone;
    let safetyPingSent = false;
    if (ownerPhone) {
      // WRAPPED, because the APPROVED write above has already committed. otp.issue THROWS
      // a ServiceUnavailableException when the transport reports non-delivery — so an
      // unguarded await here meant a Twilio outage produced: claim APPROVED, 72h window
      // silently running, admin looking at a 500 and reasonably concluding nothing
      // happened, and the notifySubmitter below never reached — the claimant told nothing
      // at all. The one action whose whole purpose is a deliberate delay would have been
      // started by an operation everyone believed had failed.
      //
      // Swallowing is right HERE specifically because this ping is not load-bearing: see
      // the note below and DECISIONS §15 — nothing consumes a response to it. It is
      // logged at error level because "the deceased's number was never pinged" is a fact
      // the reviewing human needs, and returned so the caller can say so on screen.
      try {
        await this.otp.issue(ownerPhone, 'death_claim_safety_check', claim.will.ownerId);
        safetyPingSent = true;
      } catch (e) {
        this.logger.error(
          `Claim ${claimId} is APPROVED and its ${
            this.config.get('DEATH_CLAIM_SAFETY_WINDOW_HOURS') ?? 72
          }h window is running, but the safety-check ping to the owner's phone FAILED: ${(e as Error).message}`,
        );
      }
      // This is NOT a code anyone is meant to enter — no flow would accept it. It pings
      // the number and logs delivery, and that is the whole of it. This comment used to
      // claim that a response (login, app open, support contact) "should auto-reject the
      // claim" — no such auto-reject exists anywhere in the backend, so nothing consumes
      // a response and this is NOT a liveness signal. What guards a release is human
      // review, the delay below, a SEALED will and a CONFIRMED trustee. DECISIONS §15.
    }

    // Keep the person who filed the claim informed — they were previously left in
    // the dark for the entire review.
    await this.notifySubmitter(
      claim.submittedByPhone,
      'Wasiati: your death claim has been approved and is in its final verification step. We will contact you once the will is released.',
    );

    const updated = await this.prisma.deathClaim.findUnique({ where: { id: claimId } });
    return { ...updated, safetyPingSent };
  }

  async reject(claimId: string, reason: string, adminUserId: string) {
    // A released claim is terminal — its data hand-off and purge clock have started, so
    // it must not be flippable to REJECTED. An already-rejected claim is a no-op guard.
    const res = await this.prisma.deathClaim.updateMany({
      where: { id: claimId, status: { in: ['SUBMITTED', 'UNDER_REVIEW', 'APPROVED'] } },
      data: { status: 'REJECTED', rejectionReason: reason, reviewedBy: adminUserId, reviewedAt: new Date() },
    });
    if (res.count === 0) {
      throw new BadRequestException('This claim can no longer be rejected (already released or rejected).');
    }
    const updated = await this.prisma.deathClaim.findUniqueOrThrow({ where: { id: claimId } });

    await this.notifySubmitter(
      updated.submittedByPhone,
      `Wasiati: your death claim could not be verified. Reason: ${reason}. Please contact support if you believe this is a mistake.`,
    );

    return updated;
  }

  /**
   * Best-effort nudge to every admin that the review queue has a new item.
   *
   * Deliberately per-admin try/catch: by the time this runs the claim is durably
   * filed and listPendingReview will surface it regardless, so the email is a
   * convenience, not the mechanism. Letting a send failure escape would hand the
   * claimant a 500 for a claim we ACCEPTED — they would file it again, and the queue
   * would fill with duplicates of the same death. One unmailable admin (a bad address
   * on an admin row, SMTP down) must also not silence the rest of the loop.
   */
  private async notifyAdmins(subject: string, body: string) {
    const admins = await this.prisma.user.findMany({ where: { role: 'ADMIN' }, select: { id: true, email: true } });
    for (const admin of admins) {
      try {
        await this.notifications.sendEmail(admin.email, subject, body);
      } catch (e) {
        // Log the id, not the address — admin emails are PII and this is a hot path.
        this.logger.error(`Could not notify admin ${admin.id} of a new death claim: ${(e as Error).message}`);
      }
    }
  }

  /**
   * Best-effort SMS to the claimant. A notification failure must never roll back
   * or block an admin's decision on the claim itself.
   */
  private async notifySubmitter(phone: string | null | undefined, body: string) {
    if (!phone) return;
    try {
      await this.notifications.sendSms(phone, body);
    } catch (e) {
      this.logger.error(`Could not notify claim submitter ${phone}: ${(e as Error).message}`);
    }
  }

  /**
   * Final release step — called once the safety-check window has passed with no
   * response from the deceased's account, AND the trustee has separately confirmed
   * via their own SMS code (see TrusteesService.confirm). Call this from a scheduled
   * job or an admin action once both conditions are met.
   */
  async release(claimId: string, adminUserId: string) {
    const claim = await this.prisma.deathClaim.findUnique({
      where: { id: claimId },
      include: { will: { include: { owner: true, trustees: true, heirContacts: true } } },
    });
    if (!claim) throw new NotFoundException('Claim not found.');
    if (claim.status !== 'APPROVED') {
      throw new BadRequestException('Claim must be approved before release.');
    }

    // The window MUST elapse before release: without it one admin could approve and
    // release in the same second, collapsing the cooling-off period entirely. It buys
    // time for a human to notice — it is NOT a proof-of-life, because nothing watches
    // for a response from the account-holder. See DECISIONS §15 before restoring any
    // "the owner can respond and stop this" reading of the window.
    const windowHours = Number(this.config.get('DEATH_CLAIM_SAFETY_WINDOW_HOURS') ?? 72);
    if (!claim.safetyCheckSentAt) {
      throw new BadRequestException('The safety-check has not been sent; approve the claim first.');
    }
    const elapsedMs = Date.now() - new Date(claim.safetyCheckSentAt).getTime();
    if (elapsedMs < windowHours * 60 * 60 * 1000) {
      const readyAt = new Date(new Date(claim.safetyCheckSentAt).getTime() + windowHours * 60 * 60 * 1000);
      throw new BadRequestException(
        `The ${windowHours}h safety-check window has not elapsed. Release is available after ${readyAt.toISOString()}.`,
      );
    }

    // Can only release an executed will — one the owner signed and witnesses sealed.
    if (claim.will.status !== 'SEALED') {
      throw new BadRequestException('This will was never sealed (owner + witnesses signatures incomplete); it cannot be released.');
    }

    const confirmedTrustees = claim.will.trustees.filter((t) => t.status === 'CONFIRMED');
    if (confirmedTrustees.length === 0) {
      throw new BadRequestException('At least one trustee must confirm before release.');
    }

    await this.assertHeirGateSatisfied(claim);

    const releasedAt = new Date();
    // ATOMIC, with the source state in the WHERE — matching markUnderReview, approve and
    // reject. release() was the last transition still doing read-check-then-unconditional
    // write, and it is the one that matters most, because everything it triggers is
    // irreversible.
    //
    // Two things the `if (claim.status !== 'APPROVED')` check above cannot stop on its own,
    // both of which end with an estate disclosed:
    //
    //  * A reject landing in the gap. Admin A starts a release and reads APPROVED. Admin B
    //    rejects the claim — perhaps having just recognised the certificate as forged; that
    //    transition IS atomic, so it succeeds. Admin A's unconditional `update` by id then
    //    writes RELEASED straight over the REJECTED, and the fraud is handed the estate by
    //    the very action taken to stop it.
    //  * Two releases racing. Both pass the check, both write, and both run the hand-off —
    //    so every heir, trustee and witness is emailed the release notice twice, and the
    //    purge deadline is stamped twice. Being told twice that a parent's will has been
    //    released is not a cosmetic duplicate.
    //
    // Losing the race is a CONFLICT, not a bad request: the caller did nothing wrong, the
    // world moved under them, and they need to re-read the claim before deciding again.
    const res = await this.prisma.deathClaim.updateMany({
      where: { id: claimId, status: 'APPROVED' },
      data: { status: 'RELEASED', releasedAt, releasedBy: adminUserId },
    });
    if (res.count === 0) {
      throw new ConflictException(
        'This claim is no longer approved — it was released or rejected while this release was being prepared. Re-open it and check its current state before acting.',
      );
    }

    // Attribution AFTER the write wins, never before: logging the release first would
    // record releases that then lost the race and never happened. Two-person integrity —
    // the releasing admin is recorded even when it is the same person who approved, so a
    // single-actor release is visible. Persisted on the claim (releasedBy) as well as
    // logged, because logs rotate and the audit trail must not.
    this.logger.log(
      `Death claim ${claimId} released by admin ${adminUserId} (approved by ${claim.reviewedBy ?? 'unknown'}).`,
    );

    // Start the posthumous retention clock: the heirs have the retention window
    // (default 90 days) to retrieve everything, after which the daily job erases
    // ALL of the deceased's data.
    const deadline = this.retention.purgeDeadline(releasedAt);
    await this.prisma.user.update({
      where: { id: claim.will.ownerId },
      data: { scheduledPurgeAt: deadline },
    });
    // THE HAND-OVER. This replaced a `// TODO: trigger actual decryption hand-off / heir
    // access links here` that had been the entire content of "release" — the claim flipped
    // to RELEASED, the 90-day purge clock started, and nobody who mattered was told.
    //
    // sendReleaseNotice now reaches the HEIRS as well as the witnesses and trustees (its
    // recipient list read only witnesses and trustees, so the beneficiaries were contacted
    // by nothing at all), and the copy points them at the heir & trustee portal instead of
    // at a sign-in none of them has. No token travels in that email: they arrive with their
    // address and are sent a one-time code, so a forwarded release notice hands over
    // nothing. See PortalService.
    //
    // Everything below is BEST-EFFORT and wrapped, because the release itself is already
    // committed above. Before this, a single throwing send unwound nothing but propagated a
    // 500 out of an admin action that had SUCCEEDED — leaving an admin who saw an error
    // staring at an estate that was, in fact, released.
    try {
      await this.retention.sendReleaseNotice(claim.will.ownerId, deadline);
    } catch (e) {
      this.logger.error(`Release notices failed for claim ${claimId}: ${(e as Error).message}`);
    }

    // The email to `claim.will.owner.email` that used to sit here is GONE. It announced
    // "the will has been released to designated heirs" to the DECEASED'S OWN INBOX — an
    // address whose owner is, by the premise of this entire code path, dead. It reached
    // nobody it was meant to reach, and it was the one notification in this method that
    // could throw after the database write had committed.

    // Close the loop with whoever filed the claim. (notifySubmitter swallows its own
    // failures, so this cannot escape either.)
    await this.notifySubmitter(
      claim.submittedByPhone,
      'Wasiati: the will has been verified and released. Everyone named on it has been emailed a link to the heir & trustee portal.',
    );

    return { released: true };
  }

  /**
   * Every REACHABLE heir must have confirmed, or a trustee must have overridden.
   *
   * The gate the prototype designs: "The will is released once every registered heir
   * confirms — or the trustee overrides." Release is irreversible and starts a purge clock,
   * so the people it belongs to get a say before it fires.
   *
   * REACHABLE excludes two groups, and the exclusions are what stop this gate becoming a
   * deadlock rather than a safeguard:
   *   - MINORS. A child cannot give consent to the release of the estate they inherit, and
   *     their contact details route to a guardian in any case.
   *   - heirs with NEITHER a phone NOR an email. They cannot be asked, so waiting on them
   *     is waiting forever.
   *
   * If NOBODY is reachable the gate is VACUOUS and release proceeds on the conditions that
   * already existed. That is deliberate: a will whose heirs were entered without contact
   * details would otherwise be permanently unreleasable, which converts a safeguard into
   * data loss at the 90-day purge.
   *
   * KNOWN LIMIT, stated rather than hidden: an heir with a phone but no EMAIL counts as
   * reachable and so blocks release, yet the portal signs in by email only — they cannot
   * confirm, and only a trustee override clears them.
   *
   * This comment used to close by asserting that "the product requires an email on every
   * heir before a will can be sealed", which was never true — nothing enforced it, on any
   * path. seal() now runs assertSomeoneCanBeHandedTheEstate, which is a weaker and more
   * honest promise: at least ONE party on the roster (heir or trustee) carries an address,
   * so a released estate always reaches somebody. A phone-only heir alongside an
   * addressable one still lands in the limit above.
   */
  private async assertHeirGateSatisfied(claim: {
    id: string;
    trusteeOverrideAt: Date | null;
    will: { heirContacts: { id: string; isMinor: boolean; phone: string | null; email: string | null }[] };
  }): Promise<void> {
    if (claim.trusteeOverrideAt) return;

    const reachable = claim.will.heirContacts.filter((h) => !h.isMinor && (h.phone || h.email));
    if (reachable.length === 0) return; // vacuous

    const confirmations = await this.prisma.heirReleaseConfirmation.findMany({
      where: { claimId: claim.id },
      select: { heirContactId: true },
    });
    const confirmed = new Set(confirmations.map((c) => c.heirContactId));
    const parties = DeathClaimsService.askableParties(reachable);
    const outstanding = parties.filter((rows) => !rows.some((h) => confirmed.has(h.id))).length;
    if (outstanding > 0) {
      // A COUNT, never names or contact details: this message is shown to an admin, but the
      // roster of a private will is not theirs to read out of an error string.
      throw new BadRequestException(
        `${outstanding} of ${parties.length} heir(s) have not confirmed the release. ` +
          'They can confirm in the heir & trustee portal, or a trustee can override.',
      );
    }
  }

  /**
   * Reachable heirs grouped into the parties the portal can actually ASK — one group per
   * distinct sign-in address.
   *
   * The portal signs in by email, and resolveParty binds the session to the FIRST roster row
   * carrying that address. So when a testator records two adult sons on one family email —
   * ordinary, and nothing prevents it at seal — the second row is permanently unconfirmable:
   * whichever brother signs in, he is bound to the same row, and /portal/claim even reports
   * `myConfirmationPending: false` to the second one, telling him he is done. The gate then
   * blocks release forever and only a trustee override clears it.
   *
   * Requiring one answer per ROW requires something the system cannot solicit. That is the
   * same reasoning already applied to an heir with no contact details at all, who is not
   * waited on because they cannot be asked — this extends it to heirs who can only be asked
   * together. Phone-only rows stay distinct: they have no shared sign-in address to collide
   * on, and each is its own party.
   *
   * Honest about what it trades: one brother's confirmation now speaks for the mailbox, not
   * just for himself. That is weaker than one-answer-per-heir — and it is the strongest thing
   * available when the testator gave both heirs one address. The durable fix is upstream, in
   * refusing duplicate heir contacts before a will is sealed; that changes what an owner may
   * record and is not something to slip in behind a release gate.
   */
  static askableParties<T extends { id: string; email: string | null }>(reachable: T[]): T[][] {
    const groups = new Map<string, T[]>();
    for (const h of reachable) {
      const key = h.email?.trim() ? `email:${h.email.trim().toLowerCase()}` : `row:${h.id}`;
      const existing = groups.get(key);
      if (existing) existing.push(h);
      else groups.set(key, [h]);
    }
    return [...groups.values()];
  }
}
