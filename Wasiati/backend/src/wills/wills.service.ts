import { validateHeirSet } from './heir-validation';
import { Injectable, BadRequestException, ForbiddenException, Logger, NotFoundException } from '@nestjs/common';
import { Prisma, SubscriptionTier, WillStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { OtpService } from '../auth/otp.service';
import { NotificationsService } from '../notifications/notifications.service';
import { AuditService } from '../common/audit/audit.service';
import { calculateShariaShares, validateBequests, HeirInput, Madhhab, BAYT_AL_MAL } from './sharia-calculator';
import { shareBasis } from './share-basis';
import { sanitizeWillText } from './text-sanitize';
import { CURRENT_DISCLAIMER_VERSION } from './disclaimer';

const TIER_RANK: Record<SubscriptionTier, number> = {
  BASIC: 0,
  STANDARD: 1,
  PREMIUM: 2,
  ULTIMATE: 3,
};

// A client keeps at most one PUBLISHED (sealed) will, plus up to a few working drafts.
//
// The one-sealed limit is enforced where it belongs — at sign time, since only one will
// may ever leave DRAFT (see sign()). This constant caps the UNSEALED working copies: the
// drafts a person is still building, plus any that are mid-ceremony (SIGNED / WITNESSED, on
// their way to sealed but not there yet). Three, so someone can line up a will per person
// they provide for, or keep alternatives side by side, without it becoming a junk drawer.
// SUPERSEDED wills (replaced by a sealed revision) are history and never count.
const MAX_UNSEALED_WILLS = 3;

/** OtpCode.purpose for the delete/unpublish re-authentication (spec §3 step-up auth). */
export const WILL_STEP_UP_PURPOSE = 'will_step_up';

/** Every will that isn't SUPERSEDED history — what the wills LIST shows. */
const LIVE_STATUSES: WillStatus[] = [
  WillStatus.DRAFT,
  WillStatus.SIGNED,
  WillStatus.WITNESSED,
  WillStatus.SEALED,
];

/** In-progress (not yet sealed) wills — what MAX_UNSEALED_WILLS caps. */
const UNSEALED_STATUSES: WillStatus[] = [
  WillStatus.DRAFT,
  WillStatus.SIGNED,
  WillStatus.WITNESSED,
];

@Injectable()
export class WillsService {
  private readonly logger = new Logger(WillsService.name);

  constructor(
    private prisma: PrismaService,
    private entitlements: EntitlementsService,
    private otp: OtpService,
    private notifications: NotificationsService,
    private audit: AuditService,
  ) {}

  async create(
    ownerId: string,
    tier: 'BASIC' | 'STANDARD' | 'PREMIUM' | 'ULTIMATE',
    heirs: HeirInput[],
    madhhab: Madhhab = 'JUMHUR',
  ) {
    // Refuse a family that cannot exist BEFORE computing anything. The engine merges
    // duplicates, so two fathers would otherwise become one father and a will that still
    // certifies 100% — with the second entry silently gone from a document the owner signs.
    const heirErrors = validateHeirSet(heirs);
    if (heirErrors.length) throw new BadRequestException(heirErrors.join(' '));

    const shares = calculateShariaShares(heirs, madhhab);

    // Never trust the client-supplied tier to grant a benefit the user hasn't paid for.
    // Clamp it DOWN to the user's actual entitlement: a BASIC payer cannot stamp a will
    // STANDARD to escape the immutability lock. A free user (no plan) may still draft at
    // the requested tier — Premium capabilities are separately hard-gated by FeatureGuard
    // and entitlement is always resolved live, never from will.tier.
    const ent = await this.entitlements.resolve(ownerId);
    const effectiveTier: SubscriptionTier =
      ent.tier && TIER_RANK[tier] > TIER_RANK[ent.tier] ? ent.tier : tier;

    // Cap the number of unsealed working wills. Serializable so two concurrent creates
    // can't both read the same stale count and each slip an extra will past the limit.
    // The published (sealed) will is NOT counted here — the one-sealed rule is enforced at
    // sign() — so a client with a sealed will may still keep the full quota of drafts.
    return this.prisma.$transaction(
      async (tx) => {
        const count = await tx.will.count({
          where: { ownerId, status: { in: UNSEALED_STATUSES } },
        });
        if (count >= MAX_UNSEALED_WILLS) {
          throw new BadRequestException(
            `You can keep up to ${MAX_UNSEALED_WILLS} drafts at a time. Delete one before starting another.`,
          );
        }
        return tx.will.create({
          data: {
            ownerId,
            tier: effectiveTier,
            locked: effectiveTier === 'BASIC', // Basic is immutable the moment it's issued
            disclaimerVersion: CURRENT_DISCLAIMER_VERSION,
            disclaimerAcceptedAt: new Date(),
            shariaShares: { create: shares },
          },
          include: { shariaShares: true },
        });
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  }

  /**
   * Confirms a will exists AND belongs to the caller. Throws NotFound (never
   * Forbidden) so we don't disclose that another user's will exists. Sibling
   * resources (assets/witnesses/trustees) call this before any mutation.
   */
  async assertOwner(willId: string, ownerId: string): Promise<void> {
    const will = await this.prisma.will.findUnique({ where: { id: willId }, select: { ownerId: true } });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
  }

  async addBequest(willId: string, ownerId: string, beneficiaryName: string, sharePercent: number, notes?: string) {
    // Ownership/editability checked outside the transaction (cheap, no race worry).
    const will = await this.prisma.will.findUnique({ where: { id: willId } });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    if (will.locked || will.status !== WillStatus.DRAFT) {
      throw new ForbiddenException('This will can no longer be edited (it is signed/sealed, or a locked Basic will).');
    }

    // The 1/3 cap is a HARD Sharia rule, so the read-sum-write must be atomic:
    // Serializable isolation makes two concurrent addBequest calls conflict rather
    // than each validating against the same stale set and both committing an
    // over-1/3 total. The loser retries/aborts instead of silently exceeding 1/3.
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          const existing = await tx.bequest.findMany({ where: { willId }, select: { sharePercent: true } });
          const proposed = [
            ...existing.map((b) => ({ sharePercent: Number(b.sharePercent) })),
            { sharePercent },
          ];
          validateBequests(proposed); // throws if the SUM exceeds one third
          return tx.bequest.create({ data: { willId, beneficiaryName, sharePercent, notes } });
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (e: any) {
      // Surface the cap violation as a 400; let a serialization conflict bubble up.
      if (e?.message?.includes('one third') || e?.message?.includes('1/3') || e?.message?.includes('exceeds')) {
        throw new BadRequestException(e.message);
      }
      throw e;
    }
  }

  /**
   * Saves the owner's private "words for my family" letter. Plain text only —
   * sanitised server-side so no markup/code is ever persisted. Not part of the
   * fara'id shares, but editing is refused once the will is sealed (to preserve
   * seal integrity) or on a locked Basic will.
   */
  async updateMessage(willId: string, ownerId: string, personalMessage: string) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { ownerId: true, status: true, locked: true },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    if (will.locked) throw new ForbiddenException('This will is locked and can no longer be edited.');
    if (will.status === WillStatus.SEALED) {
      throw new ForbiddenException('Your will is sealed; it must be reopened before the message can be edited.');
    }
    return this.prisma.will.update({
      where: { id: willId },
      data: { personalMessage: sanitizeWillText(personalMessage) },
    });
  }

  /**
   * Records the guardianship of minor children (create-flow step 3). Part of the
   * will — survives sealing — but editable only while the will is a DRAFT, like
   * the message and bequests. For the 'parent' / 'islamic' modes the name/phone/
   * email are cleared (they only apply to a 'named' guardian); a named guardian's
   * contact is trimmed and stored.
   */
  async updateGuardian(
    willId: string,
    ownerId: string,
    mode: 'parent' | 'islamic' | 'named',
    name?: string,
    phone?: string,
    email?: string,
  ) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { ownerId: true, status: true, locked: true },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    if (will.locked || will.status !== WillStatus.DRAFT) {
      throw new ForbiddenException('Guardianship can only be edited while the will is a draft.');
    }
    const clean = (v: string | undefined, max: number): string | null => {
      if (mode !== 'named' || typeof v !== 'string') return null;
      const t = v.trim().slice(0, max);
      return t.length ? t : null;
    };
    return this.prisma.will.update({
      where: { id: willId },
      data: {
        guardianMode: mode,
        guardianName: clean(name, 120),
        guardianPhone: clean(phone, 40),
        guardianEmail: clean(email, 200),
      },
    });
  }

  // --- create-flow autosave (spec §3 autosave / acceptance #5) ----------------

  /** Ceiling for a stored draft snapshot — generous for counters + a 5,000-char letter. */
  private static readonly DRAFT_STATE_MAX_BYTES = 32_768;

  /**
   * The madhhab values a draft may carry — the two the picker offers.
   *
   * The engine's Madhhab type still has five, and MALIKI/SHAFII/HANBALI remain valid inputs
   * to it; they simply compute what JUMHUR computes under contemporary application (see
   * DECISIONS §21 and the alias tests in sharia-calculator.spec.ts). Accepting only two here
   * stops a client inventing a third option that the picker never offered and the document
   * would then name.
   *
   * A stored draft carrying one of the three falls through to JUMHUR below, which is a no-op
   * arithmetically — that is exactly what those three already compute — so nothing an owner
   * previously saved changes value.
   */
  private static readonly MADHHABS: Madhhab[] = ['JUMHUR', 'HANAFI'];

  /** The heir relations accepted from a draft snapshot — same set the create DTO allows. */
  private static readonly DRAFT_HEIR_RELATIONS = new Set([
    'HUSBAND', 'WIFE', 'SON', 'DAUGHTER', 'SON_SON', 'SON_DAUGHTER', 'FATHER', 'MOTHER',
    'GRANDFATHER', 'PATERNAL_GRANDMOTHER', 'MATERNAL_GRANDMOTHER', 'GRANDMOTHER',
    'FULL_BROTHER', 'FULL_SISTER', 'CONSANGUINE_BROTHER', 'CONSANGUINE_SISTER',
    'MATERNAL_SIBLING', 'FULL_NEPHEW', 'CONSANGUINE_NEPHEW', 'FULL_UNCLE',
    'CONSANGUINE_UNCLE', 'FULL_COUSIN', 'CONSANGUINE_COUSIN',
  ]);

  /** Valid heirs lifted from the snapshot, or undefined when the snapshot carries none. */
  private parseDraftHeirs(raw: unknown): HeirInput[] | undefined {
    if (!Array.isArray(raw)) return undefined;
    const heirs: HeirInput[] = [];
    for (const h of raw.slice(0, 200)) {
      const relation = (h as any)?.relation;
      const name = (h as any)?.name;
      if (typeof relation !== 'string' || !WillsService.DRAFT_HEIR_RELATIONS.has(relation)) continue;
      if (typeof name !== 'string' || !name.trim()) continue;
      heirs.push({ relation: relation as HeirInput['relation'], name: name.trim().slice(0, 120) });
    }
    return heirs;
  }

  /** wishes{sunnah,simple,local,azaa} (spec §8) — whitelisted booleans only. */
  private parseDraftWishes(raw: unknown): Record<string, boolean> | undefined {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return undefined;
    const src = raw as Record<string, unknown>;
    const wishes: Record<string, boolean> = {};
    for (const k of ['sunnah', 'simple', 'local', 'azaa']) wishes[k] = src[k] === true;
    return wishes;
  }

  /**
   * Persists the guided create flow's snapshot onto its DRAFT will. Beyond storing
   * the opaque JSON, the parts of the snapshot that ARE will content are lifted
   * onto the row so the will always mirrors the flow:
   *   - heirs + madhhab  → shariaShares recomputed (exactly as create() computes them)
   *   - wishes           → funeralWishes
   *   - words            → personalMessage (sanitised, as updateMessage does)
   *   - bequest          → the flow's single Bequest row (tracked by _bequestId inside
   *                        the stored snapshot; rows added elsewhere are never touched;
   *                        the ⅓ cap is re-validated against ALL rows)
   * Sealing clears draftState (see seal()); will content lifted here survives it.
   */
  async updateDraft(willId: string, ownerId: string, draftState: Record<string, unknown>) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { ownerId: true, status: true, locked: true, draftState: true },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    if (will.locked || will.status !== WillStatus.DRAFT) {
      throw new ForbiddenException('Only a draft will autosaves. This will has been signed or sealed.');
    }
    if (!draftState || typeof draftState !== 'object' || Array.isArray(draftState)) {
      throw new BadRequestException('draftState must be a JSON object.');
    }
    let json: string;
    try {
      json = JSON.stringify(draftState);
    } catch {
      throw new BadRequestException('draftState must be JSON-serialisable.');
    }
    if (Buffer.byteLength(json, 'utf8') > WillsService.DRAFT_STATE_MAX_BYTES) {
      throw new BadRequestException('draftState is too large (32 KB max).');
    }

    const heirs = this.parseDraftHeirs(draftState.heirs);
    const madhhab: Madhhab = WillsService.MADHHABS.includes(draftState.madhhab as Madhhab)
      ? (draftState.madhhab as Madhhab)
      : 'JUMHUR';
    const wishes = this.parseDraftWishes(draftState.wishes);
    const words = typeof draftState.words === 'string' ? sanitizeWillText(draftState.words) : undefined;

    // The flow's bequest — a name + a % of the free third (0..100). Materialised
    // only when it names a beneficiary; while incomplete it lives in the JSON only.
    const rawBequest = draftState.bequest as { name?: unknown; third?: unknown } | undefined;
    let bequest: { name: string; sharePercent: number } | null | undefined;
    if (rawBequest && typeof rawBequest === 'object') {
      const third = Math.min(Math.max(Number(rawBequest.third) || 0, 0), 100);
      const name = typeof rawBequest.name === 'string' ? rawBequest.name.trim().slice(0, 200) : '';
      // third% OF the free third == third/3 % of the estate (the ⅓ cap by construction).
      bequest = third > 0 && name ? { name, sharePercent: Math.round((third / 3) * 100) / 100 } : null;
    }

    // Precompute outside the transaction; the calculator is pure.
    const shares = heirs ? calculateShariaShares(heirs, madhhab) : undefined;

    try {
      await this.prisma.$transaction(
        async (tx) => {
          // The flow owns exactly one Bequest row, remembered inside the stored
          // snapshot as _bequestId. Rows the owner added elsewhere stay untouched.
          let bequestId = ((will.draftState as Record<string, unknown> | null)?._bequestId as string | undefined) ?? null;
          if (bequest === null && bequestId) {
            await tx.bequest.deleteMany({ where: { id: bequestId, willId } });
            bequestId = null;
          } else if (bequest) {
            const others = await tx.bequest.findMany({
              where: { willId, ...(bequestId ? { id: { not: bequestId } } : {}) },
              select: { sharePercent: true },
            });
            validateBequests([
              ...others.map((b) => ({ sharePercent: Number(b.sharePercent) })),
              { sharePercent: bequest.sharePercent },
            ]);
            if (bequestId) {
              const updated = await tx.bequest.updateMany({
                where: { id: bequestId, willId },
                data: { beneficiaryName: bequest.name, sharePercent: bequest.sharePercent },
              });
              if (updated.count === 0) bequestId = null; // row was deleted elsewhere — recreate
            }
            if (!bequestId) {
              const row = await tx.bequest.create({
                data: { willId, beneficiaryName: bequest.name, sharePercent: bequest.sharePercent },
              });
              bequestId = row.id;
            }
          }
          if (shares) {
            await tx.shariaShare.deleteMany({ where: { willId } });
            await tx.shariaShare.createMany({ data: shares.map((s) => ({ ...s, willId })) });
          }
          await tx.will.update({
            where: { id: willId },
            data: {
              draftState: { ...draftState, _bequestId: bequestId } as Prisma.InputJsonValue,
              ...(wishes !== undefined ? { funeralWishes: wishes as Prisma.InputJsonValue } : {}),
              ...(words !== undefined ? { personalMessage: words } : {}),
            },
          });
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (e: any) {
      // Surface the ⅓-cap violation as a 400, exactly like addBequest.
      if (e?.message?.includes('one third') || e?.message?.includes('1/3') || e?.message?.includes('exceeds')) {
        throw new BadRequestException(e.message);
      }
      throw e;
    }
    return this.findOne(willId, ownerId);
  }

  async findOne(willId: string, ownerId: string) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      include: { shariaShares: true, bequests: true, witnesses: true, trustees: true },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    // Attach the scriptural basis (EN + AR) to each share so the shares table can show
    // the fiqh basis, not just the relation. Derived from the stored (relation, percent);
    // no storage/migration needed, and it works for already-created wills.
    return {
      ...will,
      shariaShares: will.shariaShares.map((s) => {
        const basis = shareBasis(s.heirRelation);
        return { ...s, basisEn: basis.en, basisAr: basis.ar };
      }),
    };
  }

  async listForOwner(ownerId: string) {
    // Lightweight relations so the wills LIST can render its summary line
    // (heir count, bequest %, witness progress) without a detail fetch per will.
    // Shapes match what the client's Will.fromJson parses; witness PII
    // (fullName/phone) is deliberately not included here.
    // SUPERSEDED wills are replaced history — hidden from the list (spec §3: the
    // user holds one published will and one draft; a sealed revision replaces
    // its original automatically).
    return this.prisma.will.findMany({
      where: { ownerId, status: { in: LIVE_STATUSES } },
      include: {
        shariaShares: { select: { id: true, heirRelation: true, heirName: true, sharePercent: true } },
        bequests: { select: { id: true, beneficiaryName: true, sharePercent: true } },
        witnesses: { select: { id: true, status: true } },
      },
    });
  }

  /**
   * Testator's email plus registered city/country, for the document header
   * ("of {name} — {city, country}") and the testator signature block.
   */
  async ownerProfile(
    willId: string,
  ): Promise<{ email: string; addressCity: string | null; addressCountry: string | null }> {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { owner: { select: { email: true, addressCity: true, addressCountry: true } } },
    });
    return {
      email: will?.owner.email ?? '—',
      addressCity: will?.owner.addressCity ?? null,
      addressCountry: will?.owner.addressCountry ?? null,
    };
  }

  // --- identity: a badge, NOT a gate -----------------------------------------
  //
  // There is deliberately no `assertIdVerified` on the signing/sealing path. Spec §3
  // reads "Identity verification: required once before any will can seal", but the owner
  // OVERRODE that for v1: ID verification is optional — a trust/verified badge, never a
  // hard gate on sealing — so KSA can launch before Nafath government onboarding is done
  // (DECISIONS §0, and §16 which records this correction). A prior commit (b2bcb84) added
  // the gate by following spec §3, the lower source; it blocked every UNVERIFIED user —
  // the default — from sealing at all. Do NOT reintroduce it without a new DECISIONS entry.

  // --- execution / signing lifecycle ---------------------------------------
  // DRAFT --(owner signs)--> SIGNED --(N witnesses sign)--> WITNESSED --(owner seals)--> SEALED

  /**
   * The will must carry at least `requiredWitnesses` witness rows (schema default 2)
   * before it may enter the signing path. Without this the owner could sign a will
   * with no witnesses attached: signByOwner sets locked=true, and recomputeAfterWitness
   * can never reach the threshold, so the will was stranded at SIGNED — locked from
   * edits and impossible to seal. The client gates step 3 on the same rule; this is
   * the authority.
   */
  private async assertWitnessQuorum(willId: string) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { requiredWitnesses: true, witnesses: { select: { id: true } } },
    });
    if (!will) throw new NotFoundException('Will not found.');
    const added = will.witnesses.length;
    if (added < will.requiredWitnesses) {
      throw new BadRequestException(
        `A will needs ${will.requiredWitnesses} witnesses before it can be signed and sealed. ` +
          `Currently added: ${added}.`,
      );
    }
  }

  /** The testator applies their own signature. Locks the will from further edits. */
  async signByOwner(willId: string, ownerId: string, signatureData: string, ip?: string) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { ownerId: true, status: true, revisionOfId: true },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    if (will.status !== WillStatus.DRAFT) throw new BadRequestException('This will has already been signed.');
    if (!signatureData || !signatureData.trim()) throw new BadRequestException('A signature is required.');

    // Witness gate: refuse before locking the will, not after.
    await this.assertWitnessQuorum(willId);
    // Email gate, for exactly the same reason. Signing sets locked=true, and sealing refuses
    // an unconfirmed address — so checking only at the seal let an unverified owner sign,
    // lock the will, and THEN be refused: left holding a will they could no longer edit and
    // could not seal either. The claim is cheap and the address is the one every witness,
    // trustee and heir is contacted at.
    await this.assertEmailVerified(ownerId);
    // No ID gate here — verification is a badge, not a gate (DECISIONS §0/§16).

    // Only ONE will per client may leave DRAFT — the second is a draft-only working copy.
    // EXCEPTION (spec §3): a REVISION of the currently-published will may re-seal,
    // replacing its original, without unpublishing first. Guard + status change run in
    // one Serializable transaction so two drafts can't both be signed concurrently.
    await this.prisma.$transaction(
      async (tx) => {
        const otherActive = await tx.will.findMany({
          where: {
            ownerId,
            id: { not: willId },
            status: { in: [WillStatus.SIGNED, WillStatus.WITNESSED, WillStatus.SEALED] },
          },
          select: { id: true },
        });
        const blocking = otherActive.filter((w) => w.id !== will.revisionOfId);
        if (blocking.length > 0) {
          throw new BadRequestException(
            'You already have a published will. Unpublish or delete it first — or edit it as a revision, which replaces it when re-sealed.',
          );
        }
        await tx.will.update({
          where: { id: willId },
          data: { status: WillStatus.SIGNED, signatureData, signedAt: new Date(), signedIp: ip ?? null, locked: true },
        });
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
    // If the required witnesses ALREADY signed while the will was a DRAFT (a natural
    // owner-signs-last ceremony), advance to WITNESSED now. Otherwise the will would be
    // stuck at SIGNED forever: the only other WITNESSED trigger is a witness-confirm
    // event, which never fires again for a witness who has already signed.
    // recomputeAfterWitness re-reads status + witness count and no-ops when the
    // threshold isn't met, so this is safe when witnesses haven't signed yet.
    await this.recomputeAfterWitness(willId);
    return this.prisma.will.findUniqueOrThrow({ where: { id: willId } });
  }

  /**
   * Advances SIGNED -> WITNESSED once the required number of witnesses have signed.
   * Called by WitnessesService after each witness confirms. Never regresses SEALED.
   */
  async recomputeAfterWitness(willId: string) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { status: true, requiredWitnesses: true, witnesses: { select: { status: true } } },
    });
    if (!will || will.status !== WillStatus.SIGNED) return;
    const signed = will.witnesses.filter((w) => w.status === 'SIGNED').length;
    if (signed >= will.requiredWitnesses) {
      await this.prisma.will.update({ where: { id: willId }, data: { status: WillStatus.WITNESSED } });
    }
  }

  /**
   * Final execution — only possible once owner + required witnesses have signed.
   * Sealing PUBLISHES the will. If this will is a revision of a published will, the
   * original is atomically SUPERSEDED in the same transaction (spec §3: "editing the
   * published will opens it as a revision, which may re-seal — replacing itself —
   * without unpublishing"). A plain new draft can never seal while a will is
   * published (only a revision can).
   */
  /**
   * The owner's email must be proven before the will becomes binding.
   *
   * `emailVerified` previously gated NOTHING — it was set by the verification link and
   * read only by password reset. So a will could be created, paid for and SEALED against
   * an address nobody had ever proven they control. That address is not incidental: it is
   * where the retention notices go, where a claim invite goes, and how the heir portal
   * identifies the person. A typo at sign-up would surface years later, to a family that
   * cannot fix it.
   *
   * Gated at SEAL rather than at sign-up or payment on purpose: drafting stays frictionless
   * — a user can explore the whole product and change their mind — and the check lands
   * exactly at the legal act. NOT retroactive on existing sealed wills; this only guards
   * new seals.
   *
   * Deliberately NOT an ID-verification gate. That is a badge, not a gate (DECISIONS §17),
   * and this is a different, cheaper claim: that the mailbox we will contact you at is
   * really yours.
   */
  /**
   * Refuses to seal a will under which nobody actually inherits.
   *
   * Two ways to arrive here, and both must be stopped rather than sealed:
   *
   *  - No eligible heir was ever recorded, so the document divides nothing.
   *  - Everything went to bayt al-māl. In practice that means the estate falls to DHAWU
   *    AL-ARḤĀM — the distant kindred: a daughter's children, a sister's children, maternal
   *    uncles and aunts, the maternal grandfather. This engine does not model any of them,
   *    and it cannot: the schools use genuinely different methodologies (Ḥanafī ranks by
   *    proximity; Ḥanbalī and later Shāfiʿī have each relative step into the place of the
   *    heir they connect through), so the division is a doctrinal choice, not arithmetic.
   *
   * The danger is not the gap itself, it is what a determined owner does about it: enter a
   * daughter's son as a SON'S son. That single mislabel turns a distant relative into a full
   * residuary heir and reverses the whole division — and the document would certify it at
   * 100%. Refusing here is the honest answer: a case we cannot compute must not be sealed as
   * though we had.
   */
  private async assertSomeoneInherits(willId: string) {
    const shares = await this.prisma.shariaShare.findMany({
      where: { willId },
      select: { heirRelation: true },
    });
    const realHeirs = shares.filter((s) => s.heirRelation !== BAYT_AL_MAL);
    if (realHeirs.length > 0) return;

    throw new BadRequestException(
      shares.length === 0
        ? 'This will has no heirs recorded, so there is nothing to divide. Add the surviving family before sealing.'
        : 'Under the fara’id, this estate passes to distant kindred (dhawu al-arḥām) — for example a ' +
          'daughter’s children, a sister’s children, or a maternal uncle. Wasiati does not calculate that ' +
          'division yet, and will not seal a will it cannot compute. Please consult a qualified scholar.',
    );
  }

  /**
   * A sealed will must be RELEASABLE, and release() cannot proceed without a CONFIRMED
   * trustee — it throws "At least one trustee must confirm before release."
   *
   * seal() checked witnesses, email, heirs and entitlement, and not this. So a will could
   * be sealed with no trustee at all, or with one who never answered their invitation, and
   * it would look published and finished. Then the owner dies, the claim is approved, the
   * 72-hour window elapses — and release is refused by a condition nobody can satisfy any
   * more, because the person who would have chased the trustee is the one who died. At day
   * ninety the retention purge erases the estate that could never be handed over.
   *
   * The same reasoning already governs witnesses: assertWitnessQuorum requires that they
   * have SIGNED, not merely been invited. The product's own copy says it plainly — "your
   * two witnesses and your trustee then confirm by SMS. Nothing is released until all three
   * have." Sealing before the trustee has confirmed contradicts that sentence.
   */
  private async assertTrusteeConfirmed(willId: string) {
    const confirmed = await this.prisma.trustee.count({
      where: { willId, status: 'CONFIRMED' },
    });
    if (confirmed > 0) return;

    const invited = await this.prisma.trustee.count({ where: { willId } });
    throw new BadRequestException(
      invited === 0
        ? 'This will has no trustee. A trustee is who acts for your family when the time comes, and the will cannot be released without one — add a trustee before sealing.'
        : 'Your trustee has not confirmed yet. They were sent a link by SMS; the will cannot be released until they accept, so it cannot be sealed until they have.',
    );
  }

  /**
   * After release, the estate is handed over through the heir & trustee portal — and the
   * portal is reached by EMAIL, only. `PortalService.resolveParty` matches a sign-in
   * address against `heirContacts.email` or `trustees.email`; there is no phone route in,
   * and `DataRetentionService.recipientsForUser` likewise collects addresses and nothing
   * else. A party carrying a phone number and no address is notified by nothing and can
   * sign in nowhere.
   *
   * So a will whose whole roster is address-less can be sealed, claimed, approved and
   * RELEASED, and reach no one. The heir roll-call does not stop it: that gate goes
   * vacuous when nobody is reachable, deliberately, so an address-less roster cannot
   * deadlock release into data loss. Release therefore succeeds, starts the 90-day purge
   * clock, and at day ninety the estate is erased having been read by no one.
   *
   * The heir-contact DTO permits blank addresses on purpose — a half-typed row must still
   * save — and notes that "the UI gates the seal on completeness". That gate was client
   * side only. This is it, server side, where seal's other completeness guards already are.
   *
   * `contains: '@'` is a SHAPE test, not validation: it separates an address from a blank
   * or a placeholder like "tbd", which is what this guard is for. A determined owner can
   * still store "x@y" and satisfy it. Real format validation belongs on the DTO, and
   * putting it there would break the half-typed row that DTO deliberately allows.
   */
  private async assertSomeoneCanBeHandedTheEstate(willId: string) {
    const [heirs, trustees] = await Promise.all([
      this.prisma.willHeirContact.count({ where: { willId, email: { contains: '@' } } }),
      this.prisma.trustee.count({ where: { willId, email: { contains: '@' } } }),
    ]);
    if (heirs + trustees > 0) return;

    throw new BadRequestException(
      'Nobody on this will can be reached. When the time comes, your heirs and your trustee ' +
        'are emailed a link to the portal where the will is handed over — that is the only way ' +
        'in, so an email address is required for at least one of them. Add one for your trustee ' +
        'or for an heir before sealing.',
    );
  }

  private async assertEmailVerified(ownerId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: ownerId },
      select: { emailVerified: true },
    });
    if (!user?.emailVerified) {
      throw new BadRequestException(
        'Confirm your email address before signing. We sent you a link when you signed up — ' +
          'this is the address your witnesses, trustee and heirs will be contacted at.',
      );
    }
  }

  /**
   * Sealing requires a live paid entitlement (any tier — the paywall is "a plan",
   * not a specific one). Resolved fresh, never read from `will.tier`: entitlement
   * is what the user is NOW, and admin/comp grants resolve like any subscription.
   */
  private async assertPaidEntitlement(ownerId: string): Promise<void> {
    const ent = await this.entitlements.resolve(ownerId);
    if (!ent.tier) {
      throw new ForbiddenException(
        'Sealing a will requires an active plan. Choose one on the pricing page — your draft is saved and nothing is lost.',
      );
    }
  }

  async seal(willId: string, ownerId: string) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { ownerId: true, status: true, revisionOfId: true },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    if (will.status !== WillStatus.WITNESSED) {
      throw new BadRequestException(
        'A will can only be sealed after the owner has signed and the required witnesses have signed.',
      );
    }
    // Defense in depth — signByOwner already checks quorum, but seal is the binding act.
    // No ID gate: verification is a badge, not a gate on sealing (DECISIONS §0/§16).
    await this.assertWitnessQuorum(willId);
    await this.assertEmailVerified(ownerId);
    await this.assertSomeoneInherits(willId);
    // release() refuses without a CONFIRMED trustee, and after the owner dies nobody can
    // fix that. Sealing into an unreleasable state is worse than refusing to seal.
    await this.assertTrusteeConfirmed(willId);
    // ...and a confirmed trustee is still not enough if nobody on the roster has an
    // address, because the portal that hands the estate over is entered by email alone.
    await this.assertSomeoneCanBeHandedTheEstate(willId);
    // THE paywall, enforced where it counts. The product is paywall-at-login
    // (DECISIONS §13/§25) — but that was UI routing only, so a free account that
    // reached the API could seal a will and take the entire product without paying.
    // The revenue model deserves the same server-side guarantee residency has.
    // Sealing rather than drafting is the gate: exploring stays free, the binding
    // act is what's sold. Admins and comped demo accounts pass via resolve().
    await this.assertPaidEntitlement(ownerId);

    const sealed = await this.prisma.$transaction(
      async (tx) => {
        const published = await tx.will.findMany({
          where: { ownerId, id: { not: willId }, status: WillStatus.SEALED },
          select: { id: true },
        });
        const blocking = published.filter((p) => p.id !== will.revisionOfId);
        if (blocking.length > 0) {
          throw new BadRequestException(
            'You already have a published will. A new draft can only be sealed after the published will is unpublished or deleted — or seal a revision of it instead.',
          );
        }
        const now = new Date();
        if (will.revisionOfId) {
          // Supersede the original atomically with publishing its replacement.
          await tx.will.updateMany({
            where: { id: will.revisionOfId, status: WillStatus.SEALED },
            data: { status: WillStatus.SUPERSEDED, supersededAt: now },
          });
        }
        return tx.will.update({
          where: { id: willId },
          // Sealing clears the create-flow autosave snapshot (spec acceptance #5:
          // "sealing clears it") — funeralWishes/personalMessage stay: they are
          // will content, not flow state.
          data: { status: WillStatus.SEALED, sealedAt: now, publishedAt: now, draftState: Prisma.DbNull },
        });
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    await this.audit.log({
      actorId: ownerId,
      action: 'will.publish',
      targetType: 'Will',
      targetId: willId,
      metadata: will.revisionOfId ? { supersededWillId: will.revisionOfId } : undefined,
    });
    return sealed;
  }

  // --- step-up re-authentication (spec §3: delete/unpublish require it) -------

  /**
   * Resolves where a step-up code goes for this owner. SMS to the phone if there is one;
   * otherwise a code to the account's verified email. Every account has a unique, verified
   * email, so a phoneless owner is never dead-ended out of unpublish/delete — which was a
   * real trap, since phone is optional at registration and cannot be added later. Spec §3
   * allows a non-SMS factor ("SMS OTP, or Face ID on mobile"); email is the server-side
   * equivalent of that "or". See DECISIONS §17.
   *
   * `requestStepUpOtp` and `verifyStepUp` both resolve through here, so issue and verify
   * always key off the same (destination, purpose) pair.
   */
  private async stepUpChannel(ownerId: string): Promise<{ destination: string; channel: 'sms' | 'email' }> {
    const user = await this.prisma.user.findUnique({
      where: { id: ownerId },
      select: { phone: true, email: true },
    });
    if (!user) throw new NotFoundException('User not found.');
    return user.phone ? { destination: user.phone, channel: 'sms' } : { destination: user.email, channel: 'email' };
  }

  /**
   * Issues the one-time code that authorizes a subsequent unpublish or delete. Sent by
   * SMS when the owner has a phone, otherwise to their email (DECISIONS §17). `via` tells
   * the client which, so it can label the code-entry prompt correctly.
   */
  async requestStepUpOtp(willId: string, ownerId: string) {
    await this.assertOwner(willId, ownerId);
    const { destination, channel } = await this.stepUpChannel(ownerId);
    const code = await this.otp.issue(destination, WILL_STEP_UP_PURPOSE, ownerId, channel);
    return { sent: true, via: channel, devCode: this.otp.devEchoCode(code) };
  }

  /** Verifies (and consumes) the step-up code. Throws 400 on a missing/wrong code. */
  private async verifyStepUp(ownerId: string, otpCode?: string): Promise<void> {
    if (!otpCode?.trim()) {
      throw new BadRequestException('This action requires the confirmation code (step-up authentication).');
    }
    const { destination } = await this.stepUpChannel(ownerId);
    const ok = await this.otp.verify(destination, WILL_STEP_UP_PURPOSE, otpCode.trim());
    if (!ok) throw new BadRequestException('Invalid or expired confirmation code.');
  }

  // --- publish lifecycle: unpublish / delete / revise -------------------------

  /**
   * SEALED -> DRAFT (spec §3). Requires step-up auth. The will reopens for editing
   * (unless the historical Basic tier forbids edits); the owner's signature and all
   * witness signatures are cleared — a re-seal is a fresh ceremony — and every
   * witness who had signed is notified that the will is no longer sealed.
   */
  async unpublish(willId: string, ownerId: string, otpCode?: string, ip?: string) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      include: { witnesses: true },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    if (will.status !== WillStatus.SEALED) {
      throw new BadRequestException('Only a published (sealed) will can be unpublished.');
    }
    await this.verifyStepUp(ownerId, otpCode);

    const signedWitnesses = will.witnesses.filter((w) => w.status === 'SIGNED');
    const updated = await this.prisma.$transaction(async (tx) => {
      const u = await tx.will.update({
        where: { id: willId },
        data: {
          status: WillStatus.DRAFT,
          locked: will.tier === 'BASIC', // Basic stays immutable even as a draft
          unpublishedAt: new Date(),
          publishedAt: null,
          sealedAt: null,
          signedAt: null,
          signedIp: null,
          signatureData: null,
        },
      });
      await tx.witness.updateMany({
        where: { willId },
        data: { status: 'PENDING', signedAt: null, signatureData: null, ipAddress: null, userAgent: null, idMatchStatus: 'PENDING' },
      });
      return u;
    });

    await this.audit.log({
      actorId: ownerId,
      action: 'will.unpublish',
      targetType: 'Will',
      targetId: willId,
      ipAddress: ip,
      metadata: { witnessesNotified: signedWitnesses.length },
    });

    // Best-effort — a delivery failure must never undo the unpublish.
    for (const w of signedWitnesses) {
      const body =
        `${w.fullName}, a Wasiati will you signed as a witness has been unpublished by its owner ` +
        `and is no longer sealed. If it is sealed again you will receive a new signing code.`;
      try {
        await this.notifications.sendSms(w.phone, body);
      } catch (e) {
        this.logger.error(`Unpublish SMS to witness ${w.id} failed: ${(e as Error).message}`);
      }
      if (w.email) {
        try {
          await this.notifications.sendEmail(w.email, 'A will you witnessed was unpublished', body);
        } catch (e) {
          this.logger.error(`Unpublish email to witness ${w.id} failed: ${(e as Error).message}`);
        }
      }
    }
    return updated;
  }

  /**
   * Hard-deletes a will (spec §3: delete requires step-up auth + audit line).
   * Children (shares, bequests, witnesses, trustees, assets, claims) cascade at the
   * DB level. Refused while a non-REJECTED death claim exists — a live claim means
   * the will may be evidence. Deleting a published original detaches any revision
   * draft (revisionOfId -> null), which then behaves as a plain draft.
   */
  async remove(willId: string, ownerId: string, otpCode?: string, ip?: string) {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { ownerId: true, status: true, tier: true },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');

    const activeClaims = await this.prisma.deathClaim.count({
      where: { willId, status: { not: 'REJECTED' } },
    });
    if (activeClaims > 0) {
      throw new BadRequestException('This will has an active death claim and cannot be deleted.');
    }

    // Verify LAST so a code isn't consumed by a request that would fail anyway.
    await this.verifyStepUp(ownerId, otpCode);

    await this.prisma.will.delete({ where: { id: willId } });

    await this.audit.log({
      actorId: ownerId,
      action: 'will.delete',
      targetType: 'Will',
      targetId: willId,
      ipAddress: ip,
      metadata: { statusAtDelete: will.status, tier: will.tier },
    });
    return { deleted: true };
  }

  /**
   * Opens the published will as a DRAFT revision (spec §3: "editing the published
   * will opens it as a revision, which may re-seal — replacing itself — without
   * unpublishing"). Copies EVERY content field of the will: heirs/shares, bequests,
   * assets, the heir-contact roster, the family message, funeral wishes, the
   * guardianship of minors, and the witness/trustee roster. Witnesses reset to
   * PENDING (they must re-sign the revised content); the trustee's ROLE
   * confirmation carries over (they never see contents). The revision is the one
   * allowed draft under the ≤1+≤1 cap.
   *
   * Deliberately NOT copied — everything else on the Will model is lifecycle or
   * execution state of the ORIGINAL document, not content:
   *   - status/locked/pdfUrl, signatureData/signedAt/signedIp, sealedAt,
   *     publishedAt/unpublishedAt/supersededAt: the revision is a fresh unsigned
   *     DRAFT; the owner must re-sign it, and its PDF is regenerated at seal.
   *   - draftState: cleared at seal, so a SEALED original has none to carry.
   *   - deathClaims / claimTokens (relations): claims and access tokens attach to
   *     the specific document they were filed against, never to a copy.
   *
   * wills-revise.spec.ts enumerates the Will model via Prisma.dmmf and fails if a
   * field is added there without being classified here — heirContacts was silently
   * dropped once (revise → re-seal → release notified NOBODY); never again.
   */
  async revise(willId: string, ownerId: string) {
    const original = await this.prisma.will.findUnique({
      where: { id: willId },
      include: {
        shariaShares: true,
        bequests: true,
        witnesses: true,
        trustees: true,
        assets: true,
        heirContacts: true,
      },
    });
    if (!original || original.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    if (original.status !== WillStatus.SEALED) {
      throw new BadRequestException('Only a published (sealed) will can be revised. Edit your draft directly.');
    }
    if (original.tier === 'BASIC') {
      throw new ForbiddenException('Basic wills are immutable and cannot be revised.');
    }

    const revision = await this.prisma.$transaction(
      async (tx) => {
        // A revision is a new DRAFT, so it counts against the same unsealed-wills cap as
        // any other draft. The sealed original being revised is SEALED, not unsealed, so it
        // is not in this count — you can revise a published will while it stays published.
        const unsealed = await tx.will.count({
          where: { ownerId, status: { in: UNSEALED_STATUSES } },
        });
        if (unsealed >= MAX_UNSEALED_WILLS) {
          throw new BadRequestException(
            `You can keep up to ${MAX_UNSEALED_WILLS} drafts at a time. Delete one before opening a revision.`,
          );
        }
        return tx.will.create({
          data: {
            ownerId,
            tier: original.tier,
            locked: false,
            status: WillStatus.DRAFT,
            revisionOfId: willId,
            requiredWitnesses: original.requiredWitnesses,
            personalMessage: original.personalMessage,
            // Funeral & burial wishes and guardianship of minors are part of the
            // will's content (spec §8 / create-flow step 3) — they must survive a
            // revision exactly like the shares do. (Json? field: omit when null.)
            funeralWishes: original.funeralWishes ?? undefined,
            guardianMode: original.guardianMode,
            guardianName: original.guardianName,
            guardianPhone: original.guardianPhone,
            guardianEmail: original.guardianEmail,
            disclaimerVersion: original.disclaimerVersion,
            disclaimerAcceptedAt: original.disclaimerAcceptedAt,
            shariaShares: {
              create: original.shariaShares.map((s) => ({
                heirRelation: s.heirRelation,
                heirName: s.heirName,
                sharePercent: s.sharePercent,
              })),
            },
            bequests: {
              create: original.bequests.map((b) => ({
                beneficiaryName: b.beneficiaryName,
                sharePercent: b.sharePercent,
                notes: b.notes,
              })),
            },
            assets: {
              create: original.assets.map((a) => ({
                type: a.type,
                label: a.label,
                institution: a.institution,
                estimatedValue: a.estimatedValue,
                currency: a.currency,
                notes: a.notes,
                contactPhone: a.contactPhone,
                contactEmail: a.contactEmail,
                accountRef: a.accountRef,
              })),
            },
            // The heir-contact roster is WHO the release path notifies (and who the
            // heir-confirmation gate counts). Dropping it here was the original
            // data-loss bug: revise → re-seal → owner dies → the will released to
            // NOBODY and the retention purge destroyed it unread.
            heirContacts: {
              create: original.heirContacts.map((h) => ({
                relation: h.relation,
                name: h.name,
                phone: h.phone,
                email: h.email,
                isMinor: h.isMinor,
              })),
            },
            // Witnesses attested to the ORIGINAL content, so their signatures cannot
            // carry to a document that may say something else: fresh rows reset to
            // PENDING (status, signedAt, signatureData, ipAddress, userAgent and
            // idMatchStatus all fall back to defaults) and they re-sign the revision.
            witnesses: {
              create: original.witnesses.map((w) => ({
                fullName: w.fullName,
                phone: w.phone,
                email: w.email,
              })),
            },
            // The trustee, by contrast, confirmed taking the ROLE, not the contents
            // (they never see contents) — so their confirmation, and the evidentiary
            // ip/userAgent captured when they gave it, carry over unchanged.
            trustees: {
              create: original.trustees.map((t) => ({
                userId: t.userId,
                fullName: t.fullName,
                phone: t.phone,
                email: t.email,
                status: t.status,
                confirmedAt: t.confirmedAt,
                ipAddress: t.ipAddress,
                userAgent: t.userAgent,
              })),
            },
          },
          include: { shariaShares: true, bequests: true, witnesses: true, trustees: true, heirContacts: true },
        });
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    await this.audit.log({
      actorId: ownerId,
      action: 'will.revise',
      targetType: 'Will',
      targetId: willId,
      metadata: { revisionId: revision.id },
    });
    return revision;
  }

  // --- export gate ------------------------------------------------------------

  /**
   * Spec §3 export gate: the will PDF downloads only after the required witnesses
   * have SIGNED **and** the trustee has CONFIRMED. Throws 403 with the progress
   * spelled out; the client keeps the button disabled with this reason.
   */
  async assertExportable(willId: string, ownerId: string): Promise<void> {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: {
        ownerId: true,
        requiredWitnesses: true,
        witnesses: { select: { status: true } },
        trustees: { select: { status: true } },
      },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');

    const signed = will.witnesses.filter((w) => w.status === 'SIGNED').length;
    const trusteeConfirmed = will.trustees.some((t) => t.status === 'CONFIRMED');
    if (signed < will.requiredWitnesses || !trusteeConfirmed) {
      throw new ForbiddenException(
        `The will PDF becomes available once ${will.requiredWitnesses} witnesses have signed and the trustee has confirmed. ` +
          `Progress: ${signed} of ${will.requiredWitnesses} witnesses signed; trustee ${trusteeConfirmed ? 'confirmed' : 'not yet confirmed'}.`,
      );
    }
  }
}
