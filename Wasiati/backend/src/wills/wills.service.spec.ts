import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { WillsService, WILL_STEP_UP_PURPOSE } from './wills.service';

// Doubles for the v2.2 lifecycle deps (step-up OTP, witness notifications, audit).
const otpDouble = { issue: jest.fn().mockResolvedValue({ id: 'otp1' }), verify: jest.fn().mockResolvedValue(true), devEchoCode: jest.fn() } as any;
const notifDouble = { sendEmail: jest.fn(), sendSms: jest.fn() } as any;
const auditDouble = { log: jest.fn() } as any;

/**
 * Applies the WHERE a seal-time `count` was actually given, rather than assuming which one
 * it was. Two of seal's guards are counts over the same shape of row — the trustee gate
 * filters on `status`, the hand-over gate on `email: { contains: '@' }` — and a double that
 * ignored the filter would keep returning a passing number with either guard DELETED. The
 * filters are the guards; honouring them is what makes these tests able to fail.
 */
function matchesCount(row: any, where: any): boolean {
  if (where?.status && row.status !== where.status) return false;
  const needle = where?.email?.contains;
  if (needle && !String(row.email ?? '').includes(needle)) return false;
  return true;
}


/**
 * Guards the access-control fix: a will may only be read or mutated by its owner.
 * A mismatched owner must look identical to "does not exist" (NotFound, never a
 * Forbidden that would confirm the will exists).
 */
describe('WillsService ownership', () => {
  const OWNER = 'user-owner';
  const OTHER = 'user-attacker';

  function serviceWith(will: any, existingBequests: { sharePercent: number }[] = []) {
    const created: any[] = [];
    const tx = {
      bequest: {
        findMany: jest.fn().mockResolvedValue(existingBequests),
        create: jest.fn().mockImplementation(({ data }: any) => {
          created.push(data);
          return Promise.resolve({ id: `b${created.length}`, ...data });
        }),
      },
    };
    const prisma = {
      will: { findUnique: jest.fn().mockResolvedValue(will) },
      bequest: { create: tx.bequest.create },
      // Run the callback with the tx double (mirrors the Serializable path).
      $transaction: jest.fn().mockImplementation((fn: any) => fn(tx)),
    } as any;
    const entitlements = { resolve: jest.fn().mockResolvedValue({ tier: null }) } as any;
    return { service: new WillsService(prisma, entitlements, otpDouble, notifDouble, auditDouble), prisma, tx, created };
  }

  describe('findOne', () => {
    it('returns the will to its owner', async () => {
      const { service } = serviceWith({ id: 'w1', ownerId: OWNER, shariaShares: [], bequests: [] });
      await expect(service.findOne('w1', OWNER)).resolves.toMatchObject({ id: 'w1' });
    });

    it('hides another user’s will behind NotFound', async () => {
      const { service } = serviceWith({ id: 'w1', ownerId: OWNER });
      await expect(service.findOne('w1', OTHER)).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws NotFound when the will does not exist', async () => {
      const { service } = serviceWith(null);
      await expect(service.findOne('missing', OWNER)).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('assertOwner', () => {
    it('passes for the owner and blocks everyone else', async () => {
      const { service } = serviceWith({ ownerId: OWNER });
      await expect(service.assertOwner('w1', OWNER)).resolves.toBeUndefined();
      const denied = serviceWith({ ownerId: OWNER }).service;
      await expect(denied.assertOwner('w1', OTHER)).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('addBequest', () => {
    it('refuses to add a bequest to a will the caller does not own', async () => {
      const { service, prisma } = serviceWith({ id: 'w1', ownerId: OWNER, locked: false, bequests: [] });
      await expect(service.addBequest('w1', OTHER, 'Charity', 10)).rejects.toBeInstanceOf(NotFoundException);
      expect(prisma.bequest.create).not.toHaveBeenCalled();
    });

    it('sums ALL bequests inside the transaction and rejects a total over 1/3', async () => {
      // 30% already committed; adding 10% would make 40% > 33.34%.
      const { service, tx } = serviceWith(
        { id: 'w1', ownerId: OWNER, locked: false, status: 'DRAFT' },
        [{ sharePercent: 20 }, { sharePercent: 10 }],
      );
      await expect(service.addBequest('w1', OWNER, 'Charity', 10)).rejects.toBeInstanceOf(BadRequestException);
      expect(tx.bequest.create).not.toHaveBeenCalled();
    });

    it('allows a bequest that keeps the total within 1/3', async () => {
      const { service, tx } = serviceWith(
        { id: 'w1', ownerId: OWNER, locked: false, status: 'DRAFT' },
        [{ sharePercent: 20 }],
      );
      await expect(service.addBequest('w1', OWNER, 'Charity', 10)).resolves.toMatchObject({ beneficiaryName: 'Charity' });
      expect(tx.bequest.create).toHaveBeenCalledTimes(1);
    });

    it('re-reads existing bequests INSIDE the transaction, not from a stale pre-read', async () => {
      const { service, tx } = serviceWith(
        { id: 'w1', ownerId: OWNER, locked: false, status: 'DRAFT' },
        [{ sharePercent: 30 }],
      );
      await service.addBequest('w1', OWNER, 'Charity', 3).catch(() => undefined);
      // The sum is computed from the tx read — this is what closes the race window.
      expect(tx.bequest.findMany).toHaveBeenCalled();
    });
  });
});

describe('WillsService signing lifecycle', () => {
  const OWNER = 'user-owner';

  function svc(will: any, otherActive = 0) {
    // Stateful mock: update() mutates the row so a later findUnique reflects it — needed
    // now that signByOwner reads the will back (and re-runs recomputeAfterWitness) after
    // signing. Default the two PENDING witnesses the witness quorum requires, so the
    // signing tests exercise their own subject; a test overrides `witnesses` to vary the
    // roster. `otherActive` is how many OTHER wills are already non-DRAFT.
    let current: any = {
      requiredWitnesses: 2,
      witnesses: [{ id: 'wit1', status: 'PENDING' }, { id: 'wit2', status: 'PENDING' }],
      ...will,
    };
    const update = jest.fn().mockImplementation(({ data }: any) => {
      current = { ...current, ...data };
      return Promise.resolve(current);
    });
    const count = jest.fn().mockResolvedValue(otherActive);
    const prisma = {
      will: {
        findUnique: jest.fn().mockImplementation(() => Promise.resolve(current)),
        findUniqueOrThrow: jest.fn().mockImplementation(() => Promise.resolve(current)),
        update,
        count,
      },
      // ID verification is a badge, NOT a gate (DECISIONS §0/§16): this user is
      // idVerificationStatus UNVERIFIED and still signs and seals. Their EMAIL is
      // confirmed, because sealing gates on that and only that — a different, cheaper
      // claim (that the mailbox we will contact you at is really yours). Kept as a
      // jest.fn so the regression test below can assert WHAT the seal path reads.
      user: {
        findUnique: jest.fn().mockResolvedValue({ idVerificationStatus: 'UNVERIFIED', emailVerified: true }),
      },
      // Sealing refuses a will nobody inherits under (assertSomeoneInherits), so the share
      // roster has to exist. Defaults to one real heir — the ordinary case — and a test
      // overrides `shariaShares` to exercise the empty and bayt-al-māl-only refusals.
      shariaShare: {
        findMany: jest
          .fn()
          .mockImplementation(() => Promise.resolve(current.shariaShares ?? [{ heirRelation: 'SON' }])),
      },
      // Sealing now also refuses a will that could never be RELEASED, and release()
      // requires a CONFIRMED trustee. Counts off the same `trustees` fixture the export
      // gate below already uses, and HONOURS the status filter — a double that ignored it
      // would keep passing with the guard deleted, which is the whole point of having one.
      trustee: {
        count: jest.fn().mockImplementation(({ where }: any) => {
          const rows: any[] = current.trustees ?? [{ status: 'CONFIRMED' }];
          return Promise.resolve(rows.filter((t) => matchesCount(t, where)).length);
        }),
      },
      // ...and refuses a will nobody could be HANDED: the portal that delivers the estate
      // is entered by EMAIL alone, so an address-less roster is released to no one and
      // then purged. Defaults to one heir with an address — the ordinary case; a test
      // overrides `heirContacts` to exercise the refusal.
      willHeirContact: {
        count: jest.fn().mockImplementation(({ where }: any) => {
          const rows: any[] = current.heirContacts ?? [{ email: 'heir@example.com' }];
          return Promise.resolve(rows.filter((h) => matchesCount(h, where)).length);
        }),
      },
      // signByOwner/seal run their guards + status changes in one Serializable tx.
      // findMany models the revision-aware "other active wills" lookup; updateMany
      // models the supersede-the-original step on a revision re-seal.
      $transaction: jest.fn().mockImplementation((fn: any) =>
        fn({
          will: {
            count,
            update,
            findMany: jest
              .fn()
              .mockImplementation(() => Promise.resolve(otherActive > 0 ? [{ id: 'other-active-will' }] : [])),
            updateMany: jest.fn().mockResolvedValue({ count: 0 }),
          },
        })),
    } as any;
    // STANDARD by default: sealing now enforces the paywall (any paid tier), and the
    // ordinary case in this suite is a paying customer. The paywall describe-block
    // overrides resolve() to model the free user.
    const entitlements = { resolve: jest.fn().mockResolvedValue({ tier: 'STANDARD' }) } as any;
    return {
      service: new WillsService(prisma, entitlements, otpDouble, notifDouble, auditDouble),
      prisma,
      entitlements,
    };
  }

  describe('signByOwner', () => {
    it('DRAFT -> SIGNED, captures signature + locks', async () => {
      const { service, prisma } = svc({ ownerId: OWNER, status: 'DRAFT' });
      const res = await service.signByOwner('w1', OWNER, 'sig', '1.2.3.4');
      expect(res.status).toBe('SIGNED');
      expect(prisma.will.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ status: 'SIGNED', locked: true, signatureData: 'sig' }) }),
      );
    });
    it('rejects an empty signature', async () => {
      const { service } = svc({ ownerId: OWNER, status: 'DRAFT' });
      await expect(service.signByOwner('w1', OWNER, '   ')).rejects.toBeInstanceOf(BadRequestException);
    });
    it('cannot sign twice', async () => {
      const { service } = svc({ ownerId: OWNER, status: 'SIGNED' });
      await expect(service.signByOwner('w1', OWNER, 'sig')).rejects.toBeInstanceOf(BadRequestException);
    });
    it('non-owner gets NotFound', async () => {
      const { service } = svc({ ownerId: OWNER, status: 'DRAFT' });
      await expect(service.signByOwner('w1', 'intruder', 'sig')).rejects.toBeInstanceOf(NotFoundException);
    });
    it('refuses to sign a second will once another is already active (draft-only cap)', async () => {
      const { service, prisma } = svc({ ownerId: OWNER, status: 'DRAFT' }, 1);
      await expect(service.signByOwner('w1', OWNER, 'sig')).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.will.update).not.toHaveBeenCalled();
    });
    it('refuses to sign with fewer than the required witnesses, and does not lock the will', async () => {
      // Regression: signing with no witnesses locked the will at SIGNED forever —
      // recomputeAfterWitness could never reach the threshold, so it could not seal
      // and could not be edited.
      const { service, prisma } = svc({ ownerId: OWNER, status: 'DRAFT', requiredWitnesses: 2, witnesses: [] });
      await expect(service.signByOwner('w1', OWNER, 'sig')).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.will.update).not.toHaveBeenCalled();
    });
    it('refuses to sign with only one witness', async () => {
      const { service, prisma } = svc({
        ownerId: OWNER,
        status: 'DRAFT',
        requiredWitnesses: 2,
        witnesses: [{ id: 'wit1', status: 'PENDING' }],
      });
      await expect(service.signByOwner('w1', OWNER, 'sig')).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.will.update).not.toHaveBeenCalled();
    });
    it('signs once two witnesses are attached, even before they confirm', async () => {
      // The quorum counts witness ROWS — confirming is a separate step (SIGNED -> WITNESSED).
      const { service } = svc({
        ownerId: OWNER,
        status: 'DRAFT',
        requiredWitnesses: 2,
        witnesses: [{ id: 'wit1', status: 'PENDING' }, { id: 'wit2', status: 'PENDING' }],
      });
      const res = await service.signByOwner('w1', OWNER, 'sig');
      expect(res.status).toBe('SIGNED');
    });
    it('advances straight to WITNESSED when the witnesses already signed (owner signs last)', async () => {
      // Regression: witnesses confirming while the will was still DRAFT no-op'd; without
      // re-running the recompute on sign, the will was stuck at SIGNED forever.
      const { service, prisma } = svc({
        ownerId: OWNER,
        status: 'DRAFT',
        requiredWitnesses: 2,
        witnesses: [{ status: 'SIGNED' }, { status: 'SIGNED' }],
      });
      const res = await service.signByOwner('w1', OWNER, 'sig');
      expect(res.status).toBe('WITNESSED');
      expect(prisma.will.update).toHaveBeenCalledWith(expect.objectContaining({ data: { status: 'WITNESSED' } }));
    });
  });

  describe('recomputeAfterWitness', () => {
    it('SIGNED -> WITNESSED once required witnesses have signed', async () => {
      const { service, prisma } = svc({
        status: 'SIGNED',
        requiredWitnesses: 2,
        witnesses: [{ status: 'SIGNED' }, { status: 'SIGNED' }],
      });
      await service.recomputeAfterWitness('w1');
      expect(prisma.will.update).toHaveBeenCalledWith(expect.objectContaining({ data: { status: 'WITNESSED' } }));
    });
    it('stays SIGNED with too few witnesses', async () => {
      const { service, prisma } = svc({ status: 'SIGNED', requiredWitnesses: 2, witnesses: [{ status: 'SIGNED' }] });
      await service.recomputeAfterWitness('w1');
      expect(prisma.will.update).not.toHaveBeenCalled();
    });
    it('does not advance a DRAFT (owner has not signed)', async () => {
      const { service, prisma } = svc({ status: 'DRAFT', requiredWitnesses: 1, witnesses: [{ status: 'SIGNED' }] });
      await service.recomputeAfterWitness('w1');
      expect(prisma.will.update).not.toHaveBeenCalled();
    });
  });

  describe('seal', () => {
    it('WITNESSED -> SEALED', async () => {
      const { service, prisma } = svc({ ownerId: OWNER, status: 'WITNESSED' });
      const res = await service.seal('w1', OWNER);
      expect(res.status).toBe('SEALED');
      expect(prisma.will.update).toHaveBeenCalled();
    });
    // DECISIONS §0/§16: ID verification is a badge, never a hard gate. The svc() double
    // above builds an UNVERIFIED owner; this asserts sealing succeeds anyway AND that the
    // seal path never reads idVerificationStatus. If a future change re-adds the gate
    // (as b2bcb84 did per spec §3), user.findUnique fires here and this fails first.
    it('seals for an UNVERIFIED owner and never consults identity', async () => {
      const { service, prisma } = svc({ ownerId: OWNER, status: 'WITNESSED' });
      const res = await service.seal('w1', OWNER);
      expect(res.status).toBe('SEALED');

      // The tripwire is on WHAT the seal path reads, not on whether it reads the user at
      // all — sealing now checks emailVerified, a different and much cheaper claim. Every
      // user query on this path must select ONLY emailVerified; the moment one asks for
      // idVerificationStatus, the b2bcb84 regression is back and this fails.
      for (const call of prisma.user.findUnique.mock.calls) {
        expect(Object.keys(call[0].select ?? {})).toEqual(['emailVerified']);
      }
    });

    it('refuses to seal against an email nobody has proven they control', async () => {
      // emailVerified gated NOTHING before this: a will could be created, paid for and
      // sealed against an unconfirmed address — the same address the retention notices,
      // the claim invite and the heir portal all key on. A sign-up typo would surface
      // years later, to a family with no way to fix it.
      const { service, prisma } = svc({ ownerId: OWNER, status: 'WITNESSED' });
      prisma.user.findUnique.mockResolvedValue({ idVerificationStatus: 'VERIFIED', emailVerified: false });
      await expect(service.seal('w1', OWNER)).rejects.toThrow(/[Cc]onfirm your email/);
    });

    // The paywall, enforced where the product is actually delivered. Paywall-at-login
    // (DECISIONS §13/§25) was UI routing only — a free account that reached the API
    // could seal a will and walk away with the entire product. Sealing is the gate
    // because it is the binding act: drafting and exploring stay free.
    describe('the paywall', () => {
      it('REFUSES to seal for an account with no active plan', async () => {
        const { service, entitlements } = svc({ ownerId: OWNER, status: 'WITNESSED' });
        entitlements.resolve.mockResolvedValue({ tier: null, source: 'none' });
        await expect(service.seal('w1', OWNER)).rejects.toThrow(/requires an active plan/i);
      });

      it('a free user is refused BEFORE any state changes', async () => {
        const { service, prisma, entitlements } = svc({ ownerId: OWNER, status: 'WITNESSED' });
        entitlements.resolve.mockResolvedValue({ tier: null, source: 'none' });
        await service.seal('w1', OWNER).catch(() => undefined);
        expect(prisma.will.update).not.toHaveBeenCalled();
      });

      it('any paid tier seals — the paywall is "a plan", not a specific one', async () => {
        const { service, entitlements } = svc({ ownerId: OWNER, status: 'WITNESSED' });
        entitlements.resolve.mockResolvedValue({ tier: 'STANDARD', source: 'subscription' });
        await expect(service.seal('w1', OWNER)).resolves.toMatchObject({ status: 'SEALED' });
      });

      it('a comped demo account seals — admin/comp grants resolve like a subscription', async () => {
        const { service, entitlements } = svc({ ownerId: OWNER, status: 'WITNESSED' });
        entitlements.resolve.mockResolvedValue({ tier: 'ULTIMATE', source: 'comp' });
        await expect(service.seal('w1', OWNER)).resolves.toMatchObject({ status: 'SEALED' });
      });
    });
    // Same guarantee on the earlier binding act — owner signing must not gate on IDENTITY.
    //
    // Asserted on the SELECT rather than on "no user lookup at all", which is what this used
    // to check. That proxy was too broad: it also forbade the email check, which is a
    // different and explicitly permitted claim (DECISIONS §0/§16 make identity a badge; the
    // email gate only says the mailbox is really yours). Signing now does read the user — it
    // must read emailVerified — and the thing that must never come back is the ID status.
    it('lets an ID-UNVERIFIED owner sign (no identity gate on the signing path)', async () => {
      const { service, prisma } = svc({ ownerId: OWNER, status: 'DRAFT' });
      prisma.user.findUnique.mockResolvedValue({ emailVerified: true });
      await service.signByOwner('w1', OWNER, 'signature-data');
      for (const call of prisma.user.findUnique.mock.calls) {
        expect(call[0].select).not.toHaveProperty('idVerificationStatus');
      }
    });

    it('refuses to SIGN against an unconfirmed email — before the will is locked', async () => {
      // Signing sets locked=true and sealing refuses an unconfirmed address, so checking
      // only at the seal let an unverified owner sign, lock the will, and THEN be refused —
      // left holding a will they could neither edit nor seal. Same reasoning the witness
      // quorum is already checked here: refuse before locking, not after.
      const { service, prisma } = svc({ ownerId: OWNER, status: 'DRAFT' });
      prisma.user.findUnique.mockResolvedValue({ emailVerified: false });
      await expect(service.signByOwner('w1', OWNER, 'signature-data')).rejects.toThrow(/[Cc]onfirm your email/);
      expect(prisma.will.update).not.toHaveBeenCalled();
    });
    it('cannot seal before witnessing is complete', async () => {
      const { service } = svc({ ownerId: OWNER, status: 'SIGNED' });
      await expect(service.seal('w1', OWNER)).rejects.toBeInstanceOf(BadRequestException);
    });
    it('cannot seal with fewer than the required witnesses (defense in depth)', async () => {
      const { service, prisma } = svc({ ownerId: OWNER, status: 'WITNESSED', requiredWitnesses: 2, witnesses: [] });
      await expect(service.seal('w1', OWNER)).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.will.update).not.toHaveBeenCalled();
    });
  });
});

describe('WillsService create cap (up to 3 unsealed drafts)', () => {
  const OWNER = 'user-owner';
  const heirs = [{ relation: 'SON', name: 'Son' }] as any;

  // `existingCount` is what tx.will.count returns for UNSEALED_STATUSES — a sealed will, if
  // any, is deliberately NOT in this number, because the create cap counts only the unsealed
  // drafts. So a client with 1 sealed will and 2 drafts still passes existingCount = 2.
  function createSvc(existingCount: number) {
    const create = jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ id: 'w-new', ...data, shariaShares: [] }));
    const count = jest.fn().mockResolvedValue(existingCount);
    const prisma = {
      // create() counts + inserts inside one Serializable transaction.
      $transaction: jest.fn().mockImplementation((fn: any) => fn({ will: { count, create } })),
    } as any;
    const entitlements = { resolve: jest.fn().mockResolvedValue({ tier: null }) } as any;
    return { service: new WillsService(prisma, entitlements, otpDouble, notifDouble, auditDouble), create };
  }

  it('creates a draft while under the cap (two existing drafts)', async () => {
    const { service, create } = createSvc(2);
    await expect(service.create(OWNER, 'STANDARD', heirs)).resolves.toMatchObject({ id: 'w-new' });
    expect(create).toHaveBeenCalledTimes(1);
  });

  it('rejects the fourth draft — three unsealed drafts is the maximum', async () => {
    const { service, create } = createSvc(3);
    await expect(service.create(OWNER, 'STANDARD', heirs)).rejects.toBeInstanceOf(BadRequestException);
    expect(create).not.toHaveBeenCalled();
  });
});

describe('WillsService create-flow autosave (updateDraft)', () => {
  const OWNER = 'user-owner';

  /**
   * Stateful double for the autosave path: update() merges into the will row,
   * bequest create/updateMany/deleteMany and shariaShare deleteMany/createMany
   * are all observable, and findOne (called at the end) sees the merged row.
   */
  function draftSvc(will: any, otherBequests: { sharePercent: number }[] = []) {
    let current: any = { id: 'w1', ownerId: OWNER, status: 'DRAFT', locked: false, draftState: null, shariaShares: [], bequests: [], witnesses: [], trustees: [], ...will };
    const willUpdate = jest.fn().mockImplementation(({ data }: any) => {
      current = { ...current, ...data };
      return Promise.resolve(current);
    });
    const bequestCreate = jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ id: 'bq-flow', ...data }));
    const bequestUpdateMany = jest.fn().mockResolvedValue({ count: 1 });
    const bequestDeleteMany = jest.fn().mockResolvedValue({ count: 1 });
    const bequestFindMany = jest.fn().mockResolvedValue(otherBequests);
    const shareDeleteMany = jest.fn().mockResolvedValue({ count: 0 });
    const shareCreateMany = jest.fn().mockImplementation(({ data }: any) => {
      current.shariaShares = data;
      return Promise.resolve({ count: data.length });
    });
    const tx = {
      will: { update: willUpdate },
      bequest: { create: bequestCreate, updateMany: bequestUpdateMany, deleteMany: bequestDeleteMany, findMany: bequestFindMany },
      // findMany is what the seal-time "does anybody actually inherit?" guard reads. The
      // autosave tests seal at the end, so it has to answer with the roster this harness
      // has been accumulating rather than nothing.
      shariaShare: {
        deleteMany: shareDeleteMany,
        createMany: shareCreateMany,
        findMany: jest.fn().mockImplementation(() => Promise.resolve(current.shariaShares ?? [{ heirRelation: 'SON' }])),
      },
    };
    const prisma = {
      will: {
        findUnique: jest.fn().mockImplementation(() => Promise.resolve(current)),
        update: willUpdate,
      },
      $transaction: jest.fn().mockImplementation((fn: any) => fn(tx)),
    } as any;
    const entitlements = { resolve: jest.fn().mockResolvedValue({ tier: null }) } as any;
    return {
      service: new WillsService(prisma, entitlements, otpDouble, notifDouble, auditDouble),
      prisma, willUpdate, bequestCreate, bequestUpdateMany, bequestDeleteMany, shareDeleteMany, shareCreateMany,
      snapshot: () => current,
    };
  }

  it('stores the snapshot on a DRAFT will and returns the will', async () => {
    const { service, willUpdate } = draftSvc({});
    const res = await service.updateDraft('w1', OWNER, { step: 2, sex: 'male' });
    expect(res.id).toBe('w1');
    expect(willUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ draftState: expect.objectContaining({ step: 2, sex: 'male' }) }) }),
    );
  });

  it('recomputes the shares from the snapshot heirs, exactly as create() would', async () => {
    const { service, shareDeleteMany, shareCreateMany } = draftSvc({});
    await service.updateDraft('w1', OWNER, { heirs: [{ relation: 'SON', name: 'Yusuf' }] });
    expect(shareDeleteMany).toHaveBeenCalledWith({ where: { willId: 'w1' } });
    const rows = shareCreateMany.mock.calls[0][0].data;
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ willId: 'w1', heirRelation: 'SON', sharePercent: 100 });
  });

  it('skips malformed heirs and leaves existing shares alone when the snapshot has none', async () => {
    const { service, shareDeleteMany } = draftSvc({});
    await service.updateDraft('w1', OWNER, { step: 1 }); // no heirs key at all
    expect(shareDeleteMany).not.toHaveBeenCalled();
  });

  it('lifts wishes -> funeralWishes and words -> personalMessage (sanitised)', async () => {
    const { service, willUpdate } = draftSvc({});
    await service.updateDraft('w1', OWNER, {
      wishes: { sunnah: true, simple: false, local: true, azaa: false, evil: true },
      words: '<script>x</script>Hold to your prayers.',
    });
    expect(willUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          funeralWishes: { sunnah: true, simple: false, local: true, azaa: false },
          personalMessage: 'xHold to your prayers.',
        }),
      }),
    );
  });

  it('materialises the flow bequest as its own row and remembers the row id', async () => {
    const { service, bequestCreate, willUpdate } = draftSvc({});
    // 30% of the free third == 10% of the estate.
    await service.updateDraft('w1', OWNER, { bequest: { name: 'Local masjid', third: 30 } });
    expect(bequestCreate).toHaveBeenCalledWith({
      data: { willId: 'w1', beneficiaryName: 'Local masjid', sharePercent: 10 },
    });
    expect(willUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ draftState: expect.objectContaining({ _bequestId: 'bq-flow' }) }) }),
    );
  });

  it('updates its own bequest row on later saves instead of duplicating it', async () => {
    const { service, bequestCreate, bequestUpdateMany } = draftSvc({ draftState: { _bequestId: 'bq-flow' } });
    await service.updateDraft('w1', OWNER, { bequest: { name: 'Orphan fund', third: 60 } });
    expect(bequestUpdateMany).toHaveBeenCalledWith({
      where: { id: 'bq-flow', willId: 'w1' },
      data: { beneficiaryName: 'Orphan fund', sharePercent: 20 },
    });
    expect(bequestCreate).not.toHaveBeenCalled();
  });

  it('clears the flow bequest row when the slider returns to zero', async () => {
    const { service, bequestDeleteMany } = draftSvc({ draftState: { _bequestId: 'bq-flow' } });
    await service.updateDraft('w1', OWNER, { bequest: { name: 'Local masjid', third: 0 } });
    expect(bequestDeleteMany).toHaveBeenCalledWith({ where: { id: 'bq-flow', willId: 'w1' } });
  });

  it('re-validates the 1/3 cap against rows added outside the flow', async () => {
    // Another 30%-of-estate bequest already exists; the flow asking for 100% of the
    // free third (33.33%) would push the total past 1/3.
    const { service } = draftSvc({}, [{ sharePercent: 30 }]);
    await expect(
      service.updateDraft('w1', OWNER, { bequest: { name: 'Local masjid', third: 100 } }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('never touches bequest rows the flow does not own', async () => {
    const { service, bequestDeleteMany, bequestUpdateMany } = draftSvc({}, [{ sharePercent: 5 }]);
    await service.updateDraft('w1', OWNER, { step: 3 }); // no bequest in the snapshot
    expect(bequestDeleteMany).not.toHaveBeenCalled();
    expect(bequestUpdateMany).not.toHaveBeenCalled();
  });

  it('refuses to autosave onto a will that has left DRAFT', async () => {
    const { service } = draftSvc({ status: 'SIGNED' });
    await expect(service.updateDraft('w1', OWNER, { step: 1 })).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('hides another user’s will behind NotFound', async () => {
    const { service } = draftSvc({});
    await expect(service.updateDraft('w1', 'intruder', { step: 1 })).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects an oversized snapshot (32 KB cap)', async () => {
    const { service } = draftSvc({});
    await expect(
      service.updateDraft('w1', OWNER, { blob: 'x'.repeat(40_000) }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('sealing clears draftState so the DRAFT card disappears (acceptance #5)', async () => {
    // Reuse the signing-lifecycle double shape: a WITNESSED will with its two signed
    // witnesses, and an UNVERIFIED owner — seal re-checks the quorum but NOT identity
    // (DECISIONS §0/§16).
    let current: any = {
      id: 'w1',
      ownerId: OWNER,
      status: 'WITNESSED',
      revisionOfId: null,
      draftState: { step: 4 },
      requiredWitnesses: 2,
      witnesses: [{ id: 'wit1', status: 'SIGNED' }, { id: 'wit2', status: 'SIGNED' }],
    };
    const update = jest.fn().mockImplementation(({ data }: any) => {
      current = { ...current, ...data };
      return Promise.resolve(current);
    });
    const prisma = {
      will: { findUnique: jest.fn().mockImplementation(() => Promise.resolve(current)), update },
      // ID-unverified (a badge, not a gate — §17) but email confirmed, which sealing requires.
      user: { findUnique: jest.fn().mockResolvedValue({ idVerificationStatus: 'UNVERIFIED', emailVerified: true }) },
      // Sealing also refuses a will nobody inherits under (assertSomeoneInherits), so this
      // will needs a real heir — the point of THIS test is draftState, not the guard.
      shariaShare: { findMany: jest.fn().mockResolvedValue([{ heirRelation: 'SON' }]) },
      // seal() also requires a CONFIRMED trustee: release() cannot proceed without one, and
      // sealing into an unreleasable state is worse than refusing to seal. It likewise
      // requires SOMEONE with an email address, the portal's only way in. Both guards are
      // pinned properly in their own describe blocks; here they just need to pass, because
      // the subject of THIS test is draftState.
      trustee: { count: jest.fn().mockResolvedValue(1) },
      willHeirContact: { count: jest.fn().mockResolvedValue(1) },
      $transaction: jest.fn().mockImplementation((fn: any) =>
        fn({ will: { update, findMany: jest.fn().mockResolvedValue([]), updateMany: jest.fn().mockResolvedValue({ count: 0 }) } })),
    } as any;
    const entitlements = { resolve: jest.fn().mockResolvedValue({ tier: 'STANDARD' } /* this suite seals; sealing is paywalled */) } as any;
    const service = new WillsService(prisma, entitlements, otpDouble, notifDouble, auditDouble);
    const res = await service.seal('w1', OWNER);
    expect(res.status).toBe('SEALED');
    const sealCall = update.mock.calls.find((c: any) => c[0]?.data?.status === 'SEALED');
    expect(sealCall[0].data).toHaveProperty('draftState');
    expect(sealCall[0].data.draftState).not.toEqual({ step: 4 });
  });
});

/** Guardianship of minor children (create-flow step 3). */
describe('WillsService.updateGuardian', () => {
  const OWNER = 'user-owner';
  const OTHER = 'user-attacker';

  function make(will: any) {
    const update = jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ id: 'w1', ...will, ...data }));
    const prisma = { will: { findUnique: jest.fn().mockResolvedValue(will), update } } as any;
    const service = new WillsService(prisma, {} as any, otpDouble, notifDouble, auditDouble);
    return { service, update };
  }

  it('stores a named guardian’s trimmed contact on a draft', async () => {
    const { service, update } = make({ ownerId: OWNER, status: 'DRAFT', locked: false });
    await service.updateGuardian('w1', OWNER, 'named', '  Fatima Al-Rashid ', ' +966 50 ', '');
    expect(update).toHaveBeenCalledWith({
      where: { id: 'w1' },
      data: { guardianMode: 'named', guardianName: 'Fatima Al-Rashid', guardianPhone: '+966 50', guardianEmail: null },
    });
  });

  it('clears name/phone/email for the parent (default) mode', async () => {
    const { service, update } = make({ ownerId: OWNER, status: 'DRAFT', locked: false });
    await service.updateGuardian('w1', OWNER, 'parent', 'ignored', 'ignored', 'ignored');
    expect(update).toHaveBeenCalledWith({
      where: { id: 'w1' },
      data: { guardianMode: 'parent', guardianName: null, guardianPhone: null, guardianEmail: null },
    });
  });

  it('hides another user’s will behind NotFound', async () => {
    const { service, update } = make({ ownerId: OWNER, status: 'DRAFT', locked: false });
    await expect(service.updateGuardian('w1', OTHER, 'parent')).rejects.toBeInstanceOf(NotFoundException);
    expect(update).not.toHaveBeenCalled();
  });

  it('refuses to edit a sealed will', async () => {
    const { service, update } = make({ ownerId: OWNER, status: 'SEALED', locked: false });
    await expect(service.updateGuardian('w1', OWNER, 'parent')).rejects.toBeInstanceOf(ForbiddenException);
    expect(update).not.toHaveBeenCalled();
  });
});

/**
 * The export gate (owner's rule): a will may always be VIEWED by its owner, but the
 * PDF must not leave the platform until BOTH halves of the ceremony are done — the
 * witness quorum has SIGNED **and** the trustee has CONFIRMED (by e-sign or SMS
 * code; both land as status CONFIRMED). Each half must block on its own: a gate
 * that checked only one would hand out the document early, which is the exact
 * failure these tests exist to catch. The refusal also has to NAME what is still
 * outstanding, because the client renders that reason next to the disabled button.
 */
describe('WillsService.assertExportable — the PDF export gate', () => {
  const OWNER = 'user-owner';
  const OTHER = 'user-attacker';

  const exportService = (will: any) => {
    const prisma = { will: { findUnique: jest.fn().mockResolvedValue(will) } } as any;
    const entitlements = { resolve: jest.fn() } as any;
    return new WillsService(prisma, entitlements, otpDouble, notifDouble, auditDouble);
  };

  /** A fully-executed will: quorum signed, trustee confirmed. Override one field per test. */
  const will = (over: any = {}) => ({
    ownerId: OWNER,
    requiredWitnesses: 2,
    witnesses: [{ status: 'SIGNED' }, { status: 'SIGNED' }],
    trustees: [{ status: 'CONFIRMED' }],
    ...over,
  });

  it('allows the export once BOTH witnesses have signed and the trustee has confirmed', async () => {
    await expect(exportService(will()).assertExportable('w1', OWNER)).resolves.toBeUndefined();
  });

  it('REFUSES when the trustee has not confirmed, even with a full witness quorum', async () => {
    const svc = exportService(will({ trustees: [{ status: 'PENDING' }] }));
    await expect(svc.assertExportable('w1', OWNER)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('names the trustee as outstanding when only the trustee is missing', async () => {
    const svc = exportService(will({ trustees: [{ status: 'PENDING' }] }));
    await expect(svc.assertExportable('w1', OWNER)).rejects.toThrow(
      /2 of 2 witnesses signed; trustee not yet confirmed/i,
    );
  });

  it('REFUSES when the will has no trustee at all', async () => {
    const svc = exportService(will({ trustees: [] }));
    await expect(svc.assertExportable('w1', OWNER)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('REFUSES when only one of two witnesses signed, even with the trustee confirmed', async () => {
    const svc = exportService(will({ witnesses: [{ status: 'SIGNED' }, { status: 'PENDING' }] }));
    await expect(svc.assertExportable('w1', OWNER)).rejects.toThrow(/1 of 2 witnesses signed/i);
  });

  it('REFUSES a will with no witnesses at all, trustee confirmed or not', async () => {
    await expect(exportService(will({ witnesses: [] })).assertExportable('w1', OWNER)).rejects.toThrow(
      /0 of 2 witnesses signed/i,
    );
  });

  it('counts only SIGNED witnesses — a full-size PENDING roster is not a quorum', async () => {
    const svc = exportService(will({ witnesses: [{ status: 'PENDING' }, { status: 'PENDING' }] }));
    await expect(svc.assertExportable('w1', OWNER)).rejects.toThrow(/0 of 2 witnesses signed/i);
  });

  it('names BOTH parties as outstanding when neither half is done', async () => {
    const svc = exportService(
      will({ witnesses: [{ status: 'PENDING' }, { status: 'PENDING' }], trustees: [{ status: 'PENDING' }] }),
    );
    await expect(svc.assertExportable('w1', OWNER)).rejects.toThrow(
      /0 of 2 witnesses signed; trustee not yet confirmed/i,
    );
  });

  it('honours a will that requires more than the default two witnesses', async () => {
    const svc = exportService(
      will({ requiredWitnesses: 3, witnesses: [{ status: 'SIGNED' }, { status: 'SIGNED' }] }),
    );
    await expect(svc.assertExportable('w1', OWNER)).rejects.toThrow(/2 of 3 witnesses signed/i);
  });

  it('accepts any ONE confirmed trustee among several rows', async () => {
    const svc = exportService(will({ trustees: [{ status: 'PENDING' }, { status: 'CONFIRMED' }] }));
    await expect(svc.assertExportable('w1', OWNER)).resolves.toBeUndefined();
  });

  it('hides another user’s will behind NotFound rather than gating it', async () => {
    await expect(exportService(will()).assertExportable('w1', OTHER)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('throws NotFound for a will that does not exist', async () => {
    await expect(exportService(null).assertExportable('missing', OWNER)).rejects.toBeInstanceOf(NotFoundException);
  });
});

// The step-up flow (unpublish/delete re-auth) previously dead-ended a phoneless owner:
// verifyStepUp threw "add a phone in your profile", but no route or screen lets you add
// one, and phone is optional at registration. DECISIONS §17 falls back to the account's
// verified email. This whole flow (requestStepUpOtp / verifyStepUp / unpublish / remove)
// had NO tests before.
describe('WillsService step-up channel — SMS with a phone, email without (DECISIONS §17)', () => {
  const OWNER = 'owner-1';

  function make(user: { phone: string | null; email: string }, opts: { verify?: boolean } = {}) {
    const otp = {
      issue: jest.fn().mockResolvedValue('654321'),
      verify: jest.fn().mockResolvedValue(opts.verify ?? true),
      devEchoCode: jest.fn().mockReturnValue(undefined),
    } as any;
    const prisma: any = {
      will: {
        findUnique: jest.fn().mockResolvedValue({ ownerId: OWNER, status: 'SEALED', tier: 'STANDARD' }),
        delete: jest.fn().mockResolvedValue({ id: 'w1' }),
      },
      user: { findUnique: jest.fn().mockResolvedValue(user) },
      deathClaim: { count: jest.fn().mockResolvedValue(0) },
    };
    const service = new WillsService(prisma, {} as any, otp, notifDouble, auditDouble);
    return { service, otp, prisma };
  }

  describe('requestStepUpOtp', () => {
    it('an owner WITH a phone gets an SMS code to that phone', async () => {
      const { service, otp } = make({ phone: '+15551230000', email: 'o@x.com' });
      const res = await service.requestStepUpOtp('w1', OWNER);
      expect(res.via).toBe('sms');
      expect(otp.issue).toHaveBeenCalledWith('+15551230000', WILL_STEP_UP_PURPOSE, OWNER, 'sms');
    });

    it('a PHONELESS owner gets an email code instead of a dead-end (the trap fix)', async () => {
      const { service, otp } = make({ phone: null, email: 'o@x.com' });
      const res = await service.requestStepUpOtp('w1', OWNER);
      expect(res.via).toBe('email');
      expect(otp.issue).toHaveBeenCalledWith('o@x.com', WILL_STEP_UP_PURPOSE, OWNER, 'email');
    });
  });

  describe('remove (delete) verifies step-up on the resolved channel', () => {
    // End-to-end proof the phoneless owner is truly unblocked: delete succeeds, and the
    // code is verified against the EMAIL destination (the same one issue would send to).
    it('a phoneless owner can delete their will via an email step-up code', async () => {
      const { service, otp, prisma } = make({ phone: null, email: 'o@x.com' });
      await expect(service.remove('w1', OWNER, '654321')).resolves.toEqual({ deleted: true });
      expect(otp.verify).toHaveBeenCalledWith('o@x.com', WILL_STEP_UP_PURPOSE, '654321');
      expect(prisma.will.delete).toHaveBeenCalled();
    });

    it('an owner with a phone verifies against the phone, not the email', async () => {
      const { service, otp } = make({ phone: '+15551230000', email: 'o@x.com' });
      await service.remove('w1', OWNER, '654321');
      expect(otp.verify).toHaveBeenCalledWith('+15551230000', WILL_STEP_UP_PURPOSE, '654321');
    });

    it('a wrong/expired code still blocks the delete on the email channel', async () => {
      const { service, prisma } = make({ phone: null, email: 'o@x.com' }, { verify: false });
      await expect(service.remove('w1', OWNER, '000000')).rejects.toThrow(/invalid or expired/i);
      expect(prisma.will.delete).not.toHaveBeenCalled();
    });

    it('a missing code is refused before any OTP lookup', async () => {
      const { service, otp } = make({ phone: null, email: 'o@x.com' });
      await expect(service.remove('w1', OWNER, undefined)).rejects.toThrow(/step-up authentication/i);
      expect(otp.verify).not.toHaveBeenCalled();
    });
  });
});

/**
 * A will nobody inherits under must not be sealed.
 *
 * Two ways to get there. Either no eligible heir was recorded — the document divides nothing
 * — or the whole estate landed on bayt al-māl, which in practice means it falls to DHAWU
 * AL-ARḤĀM: a daughter's children, a sister's children, a maternal uncle. This engine models
 * none of them, and cannot without a doctrinal choice: Ḥanafī ranks distant kindred by
 * proximity, while Ḥanbalī and later Shāfiʿī have each relative step into the place of the
 * heir they connect through. Those divide the same estate differently.
 *
 * The risk is not the gap. It is what an owner does about it — entering a daughter's son as a
 * SON'S son, which turns a distant relative into a full residuary heir, reverses the division,
 * and gets certified at 100%. Refusing is the honest answer: a case the engine cannot compute
 * must not be sealed as though it had.
 */
describe('WillsService.seal — refuses a will nobody inherits under', () => {
  const OWNER = 'user-owner';

  /** A WITNESSED will ready to seal, carrying whatever share roster the test needs. */
  const sealable = (shariaShares: { heirRelation: string }[]) => {
    const will = {
      id: 'w1',
      ownerId: OWNER,
      status: 'WITNESSED',
      revisionOfId: null,
      requiredWitnesses: 2,
      witnesses: [{ id: 'a' }, { id: 'b' }],
    };
    const update = jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ ...will, ...data }));
    const prisma = {
      will: {
        findUnique: jest.fn().mockResolvedValue(will),
        update,
      },
      user: { findUnique: jest.fn().mockResolvedValue({ emailVerified: true }) },
      shariaShare: { findMany: jest.fn().mockResolvedValue(shariaShares) },
      // seal() also requires a CONFIRMED trustee and someone with an email address (the
      // portal's only way in). Both are pinned in their own describe blocks; the subject
      // of THIS suite is the share roster, so here they simply pass.
      trustee: { count: jest.fn().mockResolvedValue(1) },
      willHeirContact: { count: jest.fn().mockResolvedValue(1) },
      $transaction: jest.fn().mockImplementation((fn: any) =>
        fn({
          will: {
            findMany: jest.fn().mockResolvedValue([]),
            updateMany: jest.fn().mockResolvedValue({ count: 0 }),
            update,
          },
        }),
      ),
    } as any;
    return new WillsService(prisma, { resolve: jest.fn().mockResolvedValue({ tier: 'STANDARD' }) } as any, otpDouble, notifDouble, auditDouble);
  };

  it('refuses when the whole estate went to bayt al-māl — that is dhawu al-arḥām', async () => {
    await expect(sealable([{ heirRelation: 'BAYT_AL_MAL' }]).seal('w1', OWNER))
      .rejects.toThrow(/distant kindred|dhawu al-ar/i);
  });

  it('points at a qualified scholar instead of pretending it can compute it', async () => {
    await expect(sealable([{ heirRelation: 'BAYT_AL_MAL' }]).seal('w1', OWNER)).rejects.toThrow(/scholar/i);
  });

  it('refuses when no heir was recorded at all', async () => {
    await expect(sealable([]).seal('w1', OWNER)).rejects.toThrow(/no heirs recorded/i);
  });

  it('does NOT block an ordinary will', async () => {
    // The guard must fire only when nobody real is left — otherwise it breaks every seal.
    await expect(sealable([{ heirRelation: 'WIFE' }, { heirRelation: 'SON' }]).seal('w1', OWNER))
      .resolves.toBeDefined();
  });

  it('does NOT block a will where bayt al-māl is only PART of the division', async () => {
    // A treasury line alongside real heirs is not the dhawu al-arḥām case.
    await expect(sealable([{ heirRelation: 'WIFE' }, { heirRelation: 'BAYT_AL_MAL' }]).seal('w1', OWNER))
      .resolves.toBeDefined();
  });
});

/**
 * A sealed will must be RELEASABLE.
 *
 * seal() checked witnesses, email verification, heirs and the paywall — and not the one
 * condition release() cannot proceed without: a CONFIRMED trustee. So a will could be
 * sealed with no trustee at all, or with one who never answered their invitation, and it
 * would look published and finished. Then the owner dies, the claim is approved, the 72h
 * window elapses, and release is refused by a condition nobody can satisfy any more —
 * the person who would have chased the trustee is the one who died. At day ninety the
 * retention purge erases the estate that could never be handed over.
 *
 * The product's own copy already says it: "your two witnesses and your trustee then confirm
 * by SMS. Nothing is released until all three have."
 */
describe('WillsService.seal — refuses a will that could never be released', () => {
  const OWNER = 'user-owner';

  const sealableWith = (
    trustees: { status: string; email?: string | null }[],
    // One heir with an address by default, so the trustee tests below exercise their own
    // subject. The hand-over describe block overrides it.
    heirContacts: { email?: string | null }[] = [{ email: 'heir@example.com' }],
  ) => {
    const will = {
      id: 'w1',
      ownerId: OWNER,
      status: 'WITNESSED',
      revisionOfId: null,
      requiredWitnesses: 2,
      witnesses: [{ id: 'a' }, { id: 'b' }],
    };
    const update = jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ ...will, ...data }));
    const prisma = {
      will: { findUnique: jest.fn().mockResolvedValue(will), update },
      user: { findUnique: jest.fn().mockResolvedValue({ emailVerified: true }) },
      shariaShare: { findMany: jest.fn().mockResolvedValue([{ heirRelation: 'SON' }]) },
      // Honours whichever filter it is given, so neither guard can pass while deleted.
      trustee: {
        count: jest.fn().mockImplementation(({ where }: any) =>
          Promise.resolve(trustees.filter((t) => matchesCount(t, where)).length),
        ),
      },
      willHeirContact: {
        count: jest.fn().mockImplementation(({ where }: any) =>
          Promise.resolve(heirContacts.filter((h) => matchesCount(h, where)).length),
        ),
      },
      $transaction: jest.fn().mockImplementation((fn: any) =>
        fn({
          will: {
            findMany: jest.fn().mockResolvedValue([]),
            updateMany: jest.fn().mockResolvedValue({ count: 0 }),
            update,
          },
        }),
      ),
    } as any;
    const entitlements = { resolve: jest.fn().mockResolvedValue({ tier: 'STANDARD' }) } as any;
    return { svc: new WillsService(prisma, entitlements, otpDouble, notifDouble, auditDouble), update };
  };

  it('SEALS when a trustee has confirmed', async () => {
    const { svc } = sealableWith([{ status: 'CONFIRMED' }]);
    await expect(svc.seal('w1', OWNER)).resolves.toMatchObject({ status: 'SEALED' });
  });

  it('REFUSES when the will has no trustee at all, and says to add one', async () => {
    const { svc, update } = sealableWith([]);
    await expect(svc.seal('w1', OWNER)).rejects.toThrow(/no trustee/i);
    expect(update.mock.calls.find((c: any) => c[0]?.data?.status === 'SEALED')).toBeUndefined();
  });

  // The invitation was sent and never answered — the common case, and the one where a
  // vague error would send the owner hunting through their own settings.
  it('REFUSES when the trustee has not confirmed, and says it is waiting on them', async () => {
    const { svc } = sealableWith([{ status: 'PENDING' }]);
    await expect(svc.seal('w1', OWNER)).rejects.toThrow(/has not confirmed yet/i);
  });

  it('SEALS on ANY one confirmed trustee among several, matching release()', async () => {
    const { svc } = sealableWith([{ status: 'PENDING' }, { status: 'CONFIRMED' }]);
    await expect(svc.seal('w1', OWNER)).resolves.toMatchObject({ status: 'SEALED' });
  });

  /**
   * ...and a confirmed trustee is still not enough if nobody has an ADDRESS.
   *
   * The heir & trustee portal is the hand-over, and PortalService.resolveParty matches a
   * sign-in against `heirContacts.email` / `trustees.email`. There is no phone route in,
   * and DataRetentionService.recipientsForUser collects addresses and nothing else. So an
   * address-less roster is notified by nothing and can sign in nowhere.
   *
   * The heir roll-call does not catch it: that gate goes VACUOUS when nobody is reachable,
   * on purpose, so that an address-less roster cannot deadlock release into data loss.
   * Release therefore succeeds, starts the 90-day purge clock, and at day ninety the
   * estate is erased having been read by no one.
   *
   * The heir-contact DTO permits blank addresses deliberately — a half-typed row must
   * still save — and says "the UI gates the seal on completeness". That gate was client
   * side only, which is a gate against mistakes and not against anything else.
   */
  describe('and refuses a will nobody could be handed', () => {
    const CONFIRMED = [{ status: 'CONFIRMED' as const }];

    it('SEALS when an heir carries an address', async () => {
      const { svc } = sealableWith(CONFIRMED, [{ email: 'daughter@example.com' }]);
      await expect(svc.seal('w1', OWNER)).resolves.toMatchObject({ status: 'SEALED' });
    });

    // The trustee alone is a legitimate hand-over: acting for the family when the time
    // comes is precisely the job. An heirless roster must not block that.
    it('SEALS on the TRUSTEE’s address alone, with no heir addresses at all', async () => {
      const { svc } = sealableWith([{ status: 'CONFIRMED', email: 'trustee@example.com' }], []);
      await expect(svc.seal('w1', OWNER)).resolves.toMatchObject({ status: 'SEALED' });
    });

    // THE ONE THAT MATTERS. Every condition release() checks is satisfied here — this will
    // seals, claims, approves and releases, and reaches nobody.
    it('REFUSES when the whole roster is address-less, and does not seal', async () => {
      const { svc, update } = sealableWith([{ status: 'CONFIRMED', email: null }], [{ email: null }]);
      await expect(svc.seal('w1', OWNER)).rejects.toThrow(/nobody on this will can be reached/i);
      expect(update.mock.calls.find((c: any) => c[0]?.data?.status === 'SEALED')).toBeUndefined();
    });

    // A phone number is not a way in. This is the exact shape death-claims.service.ts
    // already flags as a known limit — an heir with a phone and no email counts as
    // "reachable" for the roll-call, yet cannot sign in — and it is what makes the
    // roll-call's own definition of reachable the wrong test to reuse here.
    it('REFUSES a roster that has phone numbers and no addresses', async () => {
      const { svc } = sealableWith(
        [{ status: 'CONFIRMED', email: null }],
        [{ email: null }, { email: null }],
      );
      await expect(svc.seal('w1', OWNER)).rejects.toThrow(/nobody on this will can be reached/i);
    });

    // Blank and placeholder rows are the realistic failure, not null: the DTO accepts any
    // string under 200 characters with no format check at all.
    it('REFUSES blank and placeholder addresses, which the heir DTO happily stores', async () => {
      for (const email of ['', '   ', 'tbd', 'ask mum']) {
        const { svc } = sealableWith([{ status: 'CONFIRMED', email: null }], [{ email }]);
        await expect(svc.seal('w1', OWNER)).rejects.toThrow(/nobody on this will can be reached/i);
      }
    });

    it('names what to do about it — an owner cannot act on “sealing failed”', async () => {
      const { svc } = sealableWith([{ status: 'CONFIRMED', email: null }], [{ email: null }]);
      await expect(svc.seal('w1', OWNER)).rejects.toThrow(/add one for your trustee or for an heir/i);
    });
  });
});
