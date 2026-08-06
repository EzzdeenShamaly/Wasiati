import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { WillsService } from './wills.service';

// Doubles for the lifecycle deps (step-up OTP, notifications, audit).
const otpDouble = { issue: jest.fn(), verify: jest.fn(), devEchoCode: jest.fn() } as any;
const notifDouble = { sendEmail: jest.fn(), sendSms: jest.fn() } as any;
const auditDouble = { log: jest.fn() } as any;

/**
 * revise() must carry EVERY content field of a will onto the revision. It once
 * dropped heirContacts (plus funeralWishes and the guardian* fields): revise a
 * will, re-seal it, die — and the release path notified NOBODY, because
 * WillHeirContact is the roster DeathClaimsService releases to, and the 90-day
 * retention purge then destroyed the will unread. Silent, and triggered by the
 * safest-looking action in the product.
 *
 * That bug was possible because nothing pinned "revision == full copy". So this
 * spec does NOT test a hand-picked list of fields: it enumerates the Will model
 * (and every copied child model) from Prisma's runtime DMMF and requires an
 * explicit disposition for each field. Add a column to schema.prisma without
 * deciding what revise() does with it, and the enumeration test fails — which is
 * exactly how the heirContacts hole would have been caught.
 */

const OWNER = 'user-owner';
const ORIGINAL_ID = 'w-orig';

/**
 * Disposition of every field on the Will model.
 *  - copied:  the revision must receive the original's exact value.
 *  - fresh:   execution/lifecycle state of the ORIGINAL document — must NOT leak
 *             onto the revision (it re-signs, re-witnesses and re-seals from scratch).
 *  - special: set by revise() itself to a value asserted individually below.
 *  - copied-rows / not-copied-rows: relations, pinned per-model further down.
 *  - infra:   DB-managed columns and inverse/backing relation fields.
 *
 * IF THIS TEST JUST FAILED after you added a field to Will: decide whether the
 * field is content (→ copy it in WillsService.revise AND list it as 'copied')
 * or per-document state (→ list it as 'fresh'/'not-copied-rows' with a comment).
 * Do not silence the test without making that call — that is the exact omission
 * that shipped the heir-roster data loss.
 */
const WILL_FIELD_PLAN: Record<string, 'copied' | 'fresh' | 'special' | 'copied-rows' | 'not-copied-rows' | 'infra'> = {
  id: 'infra', // fresh uuid
  ownerId: 'special', // set from the authenticated caller (asserted == owner)
  owner: 'infra',
  tier: 'copied',
  locked: 'fresh', // revision starts editable
  pdfUrl: 'fresh', // PDF is regenerated at seal
  personalMessage: 'copied',
  status: 'special', // must start over as DRAFT
  signatureData: 'fresh', // the owner re-signs the revised content
  signedAt: 'fresh',
  signedIp: 'fresh',
  requiredWitnesses: 'copied',
  sealedAt: 'fresh',
  publishedAt: 'fresh',
  unpublishedAt: 'fresh',
  supersededAt: 'fresh',
  revisionOfId: 'special', // links the revision to the will it replaces
  revisionOf: 'infra',
  revisions: 'infra',
  draftState: 'fresh', // cleared at seal — a SEALED original has none to carry
  funeralWishes: 'copied',
  guardianMode: 'copied',
  guardianName: 'copied',
  guardianPhone: 'copied',
  guardianEmail: 'copied',
  disclaimerVersion: 'copied',
  disclaimerAcceptedAt: 'copied',
  createdAt: 'infra',
  updatedAt: 'infra',
  shariaShares: 'copied-rows',
  bequests: 'copied-rows',
  witnesses: 'copied-rows', // rows copied, signing state reset — see plan below
  trustees: 'copied-rows', // rows copied WITH confirmation — see plan below
  deathClaims: 'not-copied-rows', // a claim is filed against a specific document
  assets: 'copied-rows',
  heirContacts: 'copied-rows', // THE release roster — the original bug
  claimTokens: 'not-copied-rows', // access tokens are minted per released document
};

/**
 * Per-relation field dispositions for every child model revise() copies.
 *  - copied: the new row must receive the original row's exact value.
 *  - reset:  signing/verification state that must NOT carry — the new row must
 *            not receive the original's value (DB defaults take over).
 * The same DMMF enumeration applies: add a column to a child model and its plan
 * here must account for it, or the test fails.
 */
const RELATION_PLANS: Record<
  string,
  { model: string; copied: string[]; reset: string[]; infra: string[] }
> = {
  shariaShares: {
    model: 'ShariaShare',
    copied: ['heirRelation', 'heirName', 'sharePercent'],
    reset: [],
    infra: ['id', 'willId', 'will', 'createdAt'],
  },
  bequests: {
    model: 'Bequest',
    copied: ['beneficiaryName', 'sharePercent', 'notes'],
    reset: [],
    infra: ['id', 'willId', 'will', 'createdAt'],
  },
  assets: {
    model: 'Asset',
    copied: ['type', 'label', 'institution', 'estimatedValue', 'currency', 'notes', 'contactPhone', 'contactEmail', 'accountRef'],
    reset: [],
    infra: ['id', 'willId', 'will', 'createdAt', 'updatedAt'],
  },
  heirContacts: {
    model: 'WillHeirContact',
    copied: ['relation', 'name', 'phone', 'email', 'isMinor'],
    reset: [],
    infra: ['id', 'willId', 'will', 'createdAt', 'updatedAt'],
  },
  // Witnesses attested to the ORIGINAL content; a revision may say something
  // else, so their signatures (and the id-match verification performed at
  // signing) cannot carry. Fresh PENDING rows; they re-sign.
  witnesses: {
    model: 'Witness',
    copied: ['fullName', 'phone', 'email'],
    reset: ['status', 'signedAt', 'signatureData', 'ipAddress', 'userAgent', 'idMatchStatus'],
    infra: ['id', 'willId', 'will', 'createdAt'],
  },
  // The trustee confirmed taking the ROLE, not the contents (they never see
  // contents) — confirmation and its evidentiary capture carry over.
  trustees: {
    model: 'Trustee',
    copied: ['userId', 'fullName', 'phone', 'email', 'status', 'confirmedAt', 'ipAddress', 'userAgent'],
    reset: [],
    infra: ['id', 'willId', 'will', 'user', 'createdAt'],
  },
};

const dmmfFields = (model: string): string[] => {
  const m = Prisma.dmmf.datamodel.models.find((x) => x.name === model);
  if (!m) throw new Error(`Model ${model} not found in the Prisma DMMF`);
  return m.fields.map((f) => f.name);
};

/** A SEALED original with every content field populated with a distinct sentinel. */
function sealedOriginal(over: any = {}) {
  return {
    id: ORIGINAL_ID,
    ownerId: OWNER,
    tier: 'STANDARD',
    locked: true,
    pdfUrl: 'https://files/SENTINEL-original.pdf',
    personalMessage: 'SENTINEL personal message',
    status: 'SEALED',
    signatureData: 'SENTINEL-owner-signature',
    signedAt: new Date('2026-01-01T00:00:00Z'),
    signedIp: '203.0.113.7',
    requiredWitnesses: 3,
    sealedAt: new Date('2026-01-02T00:00:00Z'),
    publishedAt: new Date('2026-01-02T00:00:00Z'),
    unpublishedAt: new Date('2026-01-03T00:00:00Z'),
    supersededAt: new Date('2026-01-04T00:00:00Z'),
    revisionOfId: 'w-even-older',
    draftState: { step: 4, SENTINEL: true },
    funeralWishes: { sunnah: true, simple: false, local: true, azaa: false },
    guardianMode: 'named',
    guardianName: 'Fatima Al-Rashid',
    guardianPhone: '+966501112222',
    guardianEmail: 'guardian@example.com',
    disclaimerVersion: 'v2.2',
    disclaimerAcceptedAt: new Date('2025-12-31T00:00:00Z'),
    createdAt: new Date('2025-12-30T00:00:00Z'),
    updatedAt: new Date('2026-01-04T00:00:00Z'),
    shariaShares: [
      { id: 's1', willId: ORIGINAL_ID, heirRelation: 'SON', heirName: 'Yusuf', sharePercent: 66.67, createdAt: new Date() },
      { id: 's2', willId: ORIGINAL_ID, heirRelation: 'DAUGHTER', heirName: 'Maryam', sharePercent: 33.33, createdAt: new Date() },
    ],
    bequests: [
      { id: 'b1', willId: ORIGINAL_ID, beneficiaryName: 'Local masjid', sharePercent: 10, notes: 'sadaqah jariyah', createdAt: new Date() },
    ],
    assets: [
      {
        id: 'a1', willId: ORIGINAL_ID, type: 'BANK_ACCOUNT', label: 'Al Rajhi current account',
        institution: 'Al Rajhi Bank', estimatedValue: 120000.5, currency: 'SAR', notes: 'joint access',
        contactPhone: '+966114029000', contactEmail: 'branch@alrajhi.example', accountRef: 'SA0380000000608010167519',
        createdAt: new Date(), updatedAt: new Date(),
      },
    ],
    heirContacts: [
      { id: 'h1', willId: ORIGINAL_ID, relation: 'son', name: 'Yusuf', phone: '+966555000111', email: 'yusuf@example.com', isMinor: false, createdAt: new Date(), updatedAt: new Date() },
      { id: 'h2', willId: ORIGINAL_ID, relation: 'daughter', name: 'Maryam', phone: null, email: 'maryam@example.com', isMinor: true, createdAt: new Date(), updatedAt: new Date() },
    ],
    witnesses: [
      {
        id: 'wit1', willId: ORIGINAL_ID, fullName: 'Witness One', phone: '+966555222333', email: 'w1@example.com',
        status: 'SIGNED', signedAt: new Date('2026-01-01T12:00:00Z'), signatureData: 'SENTINEL-witness-sig',
        ipAddress: '198.51.100.9', userAgent: 'SENTINEL-UA', idMatchStatus: 'MATCHED', createdAt: new Date(),
      },
    ],
    trustees: [
      {
        id: 'tr1', willId: ORIGINAL_ID, userId: 'user-trustee', fullName: 'Trustee One', phone: '+966555444555',
        email: 'trustee@example.com', status: 'CONFIRMED', confirmedAt: new Date('2026-01-01T13:00:00Z'),
        ipAddress: '198.51.100.10', userAgent: 'Trustee-UA', createdAt: new Date(),
      },
    ],
    ...over,
  };
}

/** Wires revise()'s exact prisma surface: findUnique → $transaction(count, create). */
function reviseSvc(original: any, othersInSlot = 0) {
  const create = jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ id: 'w-rev', ...data }));
  const count = jest.fn().mockResolvedValue(othersInSlot);
  const prisma = {
    will: { findUnique: jest.fn().mockResolvedValue(original) },
    $transaction: jest.fn().mockImplementation((fn: any) => fn({ will: { count, create } })),
  } as any;
  const entitlements = { resolve: jest.fn().mockResolvedValue({ tier: null }) } as any;
  const service = new WillsService(prisma, entitlements, otpDouble, notifDouble, auditDouble);
  return { service, create, count, prisma };
}

/** Runs a revise and returns the data revise() handed to will.create. */
async function reviseData(over: any = {}) {
  const { service, create } = reviseSvc(sealedOriginal(over));
  await service.revise(ORIGINAL_ID, OWNER);
  expect(create).toHaveBeenCalledTimes(1);
  return create.mock.calls[0][0].data;
}

describe('WillsService.revise — the revision is a FULL copy of the will content', () => {
  it('every field of the Will model has an explicit disposition in this spec', () => {
    // THE tripwire. A new Will column not listed in WILL_FIELD_PLAN fails here,
    // forcing the copied-vs-fresh decision that was skipped when heirContacts
    // was added. See the plan's comment for what to do.
    expect(Object.keys(WILL_FIELD_PLAN).sort()).toEqual(dmmfFields('Will').sort());
  });

  it('every field of every copied child model has an explicit disposition too', () => {
    for (const [relation, plan] of Object.entries(RELATION_PLANS)) {
      const planned = [...plan.copied, ...plan.reset, ...plan.infra].sort();
      // Same tripwire one level down: a column added to e.g. WillHeirContact
      // must be classified, or a revision would silently truncate every row.
      expect({ relation, fields: planned }).toEqual({ relation, fields: dmmfFields(plan.model).sort() });
    }
  });

  it("carries every 'copied' scalar verbatim onto the revision", async () => {
    const original = sealedOriginal();
    const data = await reviseData();
    for (const [field, plan] of Object.entries(WILL_FIELD_PLAN)) {
      if (plan !== 'copied') continue;
      expect({ field, value: data[field] }).toEqual({ field, value: original[field] });
    }
  });

  it("leaks NO 'fresh' lifecycle/execution state from the original", async () => {
    const original = sealedOriginal();
    const data = await reviseData();
    for (const [field, plan] of Object.entries(WILL_FIELD_PLAN)) {
      if (plan !== 'fresh') continue;
      // The original's sentinels are all "already executed" values, so equality
      // here means the revision inherited state it must earn again itself.
      expect({ field, value: data[field] }).not.toEqual({ field, value: original[field] });
    }
  });

  it('starts the revision as an unlocked DRAFT linked to the will it replaces', async () => {
    const data = await reviseData();
    expect(data.status).toBe('DRAFT');
    expect(data.locked).toBe(false);
    expect(data.ownerId).toBe(OWNER);
    expect(data.revisionOfId).toBe(ORIGINAL_ID); // NOT the original's own revisionOfId
  });

  it('copies every row of every copied relation, field by field', async () => {
    const original = sealedOriginal();
    const data = await reviseData();
    for (const [relation, plan] of Object.entries(RELATION_PLANS)) {
      const rows = data[relation]?.create;
      expect({ relation, count: rows?.length }).toEqual({ relation, count: original[relation].length });
      original[relation].forEach((origRow: any, i: number) => {
        for (const field of plan.copied) {
          expect({ relation, row: i, field, value: rows[i][field] }).toEqual({ relation, row: i, field, value: origRow[field] });
        }
        for (const field of plan.reset) {
          // Signing/verification state must start over: the copied row must not
          // receive the original's executed value (DB defaults → PENDING).
          expect({ relation, row: i, field, value: rows[i][field] }).not.toEqual({ relation, row: i, field, value: origRow[field] });
        }
      });
    }
  });

  it('carries the heir-contact roster — the release path notifies these people', async () => {
    // The original data-loss bug, pinned by name: without this roster a revised,
    // re-sealed will released to NOBODY and the retention purge erased it unread.
    const data = await reviseData();
    expect(data.heirContacts.create).toEqual([
      { relation: 'son', name: 'Yusuf', phone: '+966555000111', email: 'yusuf@example.com', isMinor: false },
      { relation: 'daughter', name: 'Maryam', phone: null, email: 'maryam@example.com', isMinor: true },
    ]);
  });

  it('does NOT attach the original’s death claims or claim tokens to the revision', async () => {
    const data = await reviseData();
    expect(data.deathClaims).toBeUndefined();
    expect(data.claimTokens).toBeUndefined();
  });

  it('omits funeralWishes (rather than nulling a Json field) when the original has none', async () => {
    const data = await reviseData({ funeralWishes: null });
    expect(data.funeralWishes).toBeUndefined();
  });

  it('carries empty relation rosters as empty — no phantom rows', async () => {
    const data = await reviseData({ heirContacts: [], bequests: [], assets: [] });
    expect(data.heirContacts.create).toEqual([]);
    expect(data.bequests.create).toEqual([]);
    expect(data.assets.create).toEqual([]);
  });
});

describe('WillsService.revise — guards', () => {
  it('hides another user’s will behind NotFound', async () => {
    const { service, create } = reviseSvc(sealedOriginal());
    await expect(service.revise(ORIGINAL_ID, 'user-attacker')).rejects.toBeInstanceOf(NotFoundException);
    expect(create).not.toHaveBeenCalled();
  });

  it('only a SEALED will can be revised', async () => {
    const { service, create } = reviseSvc(sealedOriginal({ status: 'DRAFT' }));
    await expect(service.revise(ORIGINAL_ID, OWNER)).rejects.toBeInstanceOf(BadRequestException);
    expect(create).not.toHaveBeenCalled();
  });

  it('Basic wills are immutable — no revision', async () => {
    const { service, create } = reviseSvc(sealedOriginal({ tier: 'BASIC' }));
    await expect(service.revise(ORIGINAL_ID, OWNER)).rejects.toBeInstanceOf(ForbiddenException);
    expect(create).not.toHaveBeenCalled();
  });

  it('allows a revision while under the draft cap (two drafts already open)', async () => {
    // The revision is a new draft, so it counts toward the unsealed-wills cap — but two
    // existing drafts leaves room for a third, so revising a published will still works.
    const { service, create } = reviseSvc(sealedOriginal(), 2);
    await service.revise(ORIGINAL_ID, OWNER);
    expect(create).toHaveBeenCalledTimes(1);
  });

  it('refuses once the draft cap is full (three unsealed drafts)', async () => {
    const { service, create } = reviseSvc(sealedOriginal(), 3);
    await expect(service.revise(ORIGINAL_ID, OWNER)).rejects.toBeInstanceOf(BadRequestException);
    expect(create).not.toHaveBeenCalled();
  });
});
