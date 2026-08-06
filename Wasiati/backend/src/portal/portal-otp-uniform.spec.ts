import { BadRequestException } from '@nestjs/common';
import { OtpService, OTP_MAX_ATTEMPTS } from '../auth/otp.service';
import { PortalService, PORTAL_OTP_ERROR_MESSAGE, PORTAL_OTP_PURPOSE } from './portal.service';

/**
 * POST /portal/start and POST /portal/verify are PUBLIC. Anyone can post an email address
 * and a code to them.
 *
 * OtpService.verify is not built for a public surface: it distinguishes "no code was ever
 * requested for this destination" from "a code was requested and has expired" from "a code
 * was requested and its attempt cap is burned". Those are useful to an authenticated user
 * fixing their own sign-in. Exposed here they are an ENUMERATION ORACLE — they tell an
 * anonymous caller which email addresses are named on a dead person's will, which is the
 * exact leak death-claims/lookup was rebuilt to close. Closing it there and reopening it
 * here would be pointless.
 *
 * Every failure comes back as PORTAL_OTP_ERROR_MESSAGE. Nothing else.
 */

/** The upstream oracle, driven against the REAL OtpService so this is not a claim on trust. */
describe('OtpService.verify really does distinguish its failures (the thing being contained)', () => {
  function otpWith(record: any) {
    const prisma: any = {
      otpCode: { findFirst: async () => record, updateMany: async () => ({ count: 1 }), update: async () => ({}) },
    };
    return new OtpService(prisma, { sendSms: async () => undefined } as any, { get: () => undefined } as any);
  }

  it('throws three DIFFERENT messages for absent / expired / capped', async () => {
    const messages: string[] = [];
    const cases = [
      null,
      { id: 'o1', expiresAt: new Date(Date.now() - 1000), attempts: 0, codeHash: 'x' },
      { id: 'o1', expiresAt: new Date(Date.now() + 60000), attempts: OTP_MAX_ATTEMPTS, codeHash: 'x' },
    ];
    for (const record of cases) {
      await otpWith(record)
        .verify('heir@x.com', PORTAL_OTP_PURPOSE, '123456')
        .catch((e) => messages.push((e as Error).message));
    }
    expect(messages).toHaveLength(3);
    expect(new Set(messages).size).toBe(3); // three distinguishable outcomes — the oracle
  });
});

describe('PortalService.verify collapses every failure into one message', () => {
  function portalWith(otp: any, opts: { party?: boolean } = {}) {
    const hasParty = opts.party !== false;
    const prisma: any = {
      deathClaim: {
        // resolveParty now ranks candidates from findMany (status priority, then recency).
        findMany: async () =>
          hasParty
            ? [
                {
                  id: 'claim-1',
                  status: 'RELEASED',
                  willId: 'will-1',
                  will: {
                    owner: { email: 'owner@x.com' },
                    heirContacts: [{ id: 'heir-1', phone: null, email: 'heir@x.com' }],
                    trustees: [],
                  },
                },
              ]
            : [],
      },
      claimAccessToken: { create: async () => ({}) },
    };
    return new PortalService(
      prisma,
      otp,
      {} as any,
      { log: async () => undefined } as any,
      { get: () => undefined } as any,
      {} as any,
      { incrWithTtl: async () => 1 } as any,
    );
  }

  const FAILURES: [string, any][] = [
    // Wrong code: OtpService RETURNS FALSE here rather than throwing, so a catch block
    // alone would have let this one through as a success.
    ['a wrong code', { verify: async () => false }],
    ['no code ever requested', { verify: async () => { throw new BadRequestException('No pending code for this destination.'); } }],
    ['an expired code', { verify: async () => { throw new BadRequestException('Code has expired.'); } }],
    ['a burned attempt cap', { verify: async () => { throw new BadRequestException('Too many incorrect attempts. Please request a new code.'); } }],
  ];

  for (const [label, otp] of FAILURES) {
    it(`answers ${label} with the one uniform message`, async () => {
      const svc = portalWith(otp);
      await expect(svc.verify('HEIR' as any, 'heir@x.com', '000000')).rejects.toThrow(PORTAL_OTP_ERROR_MESSAGE);
    });
  }

  // The fifth outcome, and the one that matters most: an address that is on NO will at all
  // must be indistinguishable from one that is.
  it('answers an address that is on no will with the same message', async () => {
    const svc = portalWith({ verify: async () => true }, { party: false });
    await expect(svc.verify('HEIR' as any, 'stranger@x.com', '123456')).rejects.toThrow(PORTAL_OTP_ERROR_MESSAGE);
  });

  it('leaks none of the three upstream messages', async () => {
    for (const [, otp] of FAILURES) {
      const svc = portalWith(otp);
      const err = (await svc.verify('HEIR' as any, 'heir@x.com', '000000').catch((e) => e)) as Error;
      expect(err.message).toBe(PORTAL_OTP_ERROR_MESSAGE);
      expect(err.message).not.toContain('No pending code');
      expect(err.message).not.toContain('Code has expired');
      expect(err.message).not.toContain('Too many incorrect attempts');
    }
  });

  it('produces ONE distinct message across all five failure shapes', async () => {
    const seen = new Set<string>();
    for (const [, otp] of FAILURES) {
      const svc = portalWith(otp);
      await svc.verify('HEIR' as any, 'heir@x.com', '000000').catch((e) => seen.add((e as Error).message));
    }
    const stranger = portalWith({ verify: async () => true }, { party: false });
    await stranger.verify('HEIR' as any, 'x@x.com', '123456').catch((e) => seen.add((e as Error).message));
    expect([...seen]).toEqual([PORTAL_OTP_ERROR_MESSAGE]);
  });
});

/**
 * The other half of the same surface: /portal/start must not answer differently for an
 * address that is on a will and one that is not.
 */
describe('PortalService.start is constant', () => {
  function startService(opts: { party: boolean; issueThrows?: boolean }) {
    const issued: string[] = [];
    const prisma: any = {
      deathClaim: {
        // resolveParty now ranks candidates from findMany (status priority, then recency).
        findMany: async () =>
          opts.party
            ? [
                {
                  id: 'claim-1',
                  status: 'APPROVED',
                  willId: 'will-1',
                  will: {
                    owner: { email: 'owner@x.com' },
                    heirContacts: [{ id: 'heir-1', phone: '+966555123456', email: 'heir@x.com' }],
                    trustees: [],
                  },
                },
              ]
            : [],
      },
    };
    const otp: any = {
      issue: async (dest: string) => {
        if (opts.issueThrows) throw new Error('sms gateway down');
        issued.push(dest);
        return '123456';
      },
    };
    return {
      svc: new PortalService(
        prisma,
        otp,
        {} as any,
        { log: async () => undefined } as any,
        { get: () => undefined } as any,
        {} as any,
        { incrWithTtl: async () => 1 } as any,
      ),
      issued,
    };
  }

  it('answers { sent: true } for a real party, a stranger, and a broken SMS gateway alike', async () => {
    const real = startService({ party: true });
    const stranger = startService({ party: false });
    const broken = startService({ party: true, issueThrows: true });

    await expect(real.svc.start('HEIR' as any, 'heir@x.com')).resolves.toEqual({ sent: true });
    await expect(stranger.svc.start('HEIR' as any, 'nobody@x.com')).resolves.toEqual({ sent: true });
    await expect(broken.svc.start('HEIR' as any, 'heir@x.com')).resolves.toEqual({ sent: true });

    expect(real.issued).toHaveLength(1);
    expect(stranger.issued).toHaveLength(0); // nothing sent, and the caller cannot tell
  });

  // "the 6-digit code sent to your registered mobile" — the roster's phone wins over the
  // address the caller typed, which is a lookup key and not a delivery target.
  it('sends to the roster PHONE when there is one, never to the address that was typed', async () => {
    const { svc, issued } = startService({ party: true });
    await svc.start('HEIR' as any, 'heir@x.com');
    expect(issued[0]).toBe('+966555123456');
  });
});
