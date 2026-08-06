import { DeathClaimsService } from './death-claims.service';

/**
 * Filing a death claim must not fail because we could not email an admin about it.
 *
 * The claim row is committed before the notification runs, and listPendingReview
 * surfaces it from the database regardless — so the email is a nudge, not the
 * mechanism. When a send threw, the claimant got a 500 for a claim that had in fact
 * been ACCEPTED, and the only sane client response (retry) would file the same death
 * twice. A real admin row with the unmailable address 'admin' made nodemailer throw
 * "No recipients defined", which is exactly how this surfaced.
 */
const CLAIM = { id: 'claim-1' };

/**
 * The claim is now filed against a claim TOKEN rather than a caller-supplied
 * willId + phone + OTP, so the principal below stands in for what the guard puts on
 * the request. The best-effort-notification invariant itself is unchanged.
 */
const PRINCIPAL: any = {
  tokenId: 'tok-1',
  willId: 'will-1',
  claimId: null,
  role: 'WITNESS',
  scope: 'CLAIM_SUBMIT',
  subjectPhone: '+15559990000',
  subjectEmail: null,
  heirContactId: null,
};

function makeService(admins: Array<{ id: string; email: string }>, sendEmail: jest.Mock) {
  const prisma: any = {
    will: {
      findUnique: async () => ({
        id: 'will-1',
        ownerId: 'owner-1',
        owner: { email: 'owner@wasiati.test', claimInitPolicy: 'BOTH' },
      }),
    },
    fileObject: { findUnique: async () => ({ id: 'f1', kind: 'death_certificate', scanStatus: 'CLEAN', userId: 'owner-1' }) },
    claimAccessToken: {
      updateMany: async () => ({ count: 1 }),
      update: async () => ({}),
      findUnique: async () => ({ subjectPhone: '+15559990000' }),
    },
    deathClaim: { create: jest.fn().mockResolvedValue(CLAIM) },
    user: { findMany: async () => admins },
  };
  prisma.$transaction = async (fn: any) => fn(prisma);
  const notifications: any = { sendEmail, sendSms: jest.fn() };
  const config: any = { get: () => undefined };
  const redis: any = { incrWithTtl: async () => 1 };
  const svc = new DeathClaimsService(prisma, notifications, {} as any, {} as any, config, redis, {} as any);
  return { svc, prisma };
}

const submit = (svc: DeathClaimsService) => svc.submitClaim(PRINCIPAL, 'Aisha', 'f1');

describe('DeathClaimsService.submitClaim — admin notification is best-effort', () => {
  it('still files the claim when an admin address is unmailable', async () => {
    const sendEmail = jest.fn().mockRejectedValue(new Error('No recipients defined'));
    const { svc, prisma } = makeService([{ id: 'a1', email: 'admin' }], sendEmail);

    await expect(submit(svc)).resolves.toEqual(CLAIM);
    expect(prisma.deathClaim.create).toHaveBeenCalled();
  });

  it('keeps notifying the remaining admins after one of them throws', async () => {
    const sendEmail = jest
      .fn()
      .mockRejectedValueOnce(new Error('No recipients defined'))
      .mockResolvedValue(undefined);
    const { svc } = makeService(
      [
        { id: 'a1', email: 'admin' },
        { id: 'a2', email: 'admin@wasiati.test' },
      ],
      sendEmail,
    );

    await expect(submit(svc)).resolves.toEqual(CLAIM);
    expect(sendEmail).toHaveBeenCalledTimes(2);
    expect(sendEmail).toHaveBeenLastCalledWith('admin@wasiati.test', expect.any(String), expect.any(String));
  });

  it('notifies every admin on the happy path', async () => {
    const sendEmail = jest.fn().mockResolvedValue(undefined);
    const { svc } = makeService(
      [
        { id: 'a1', email: 'one@wasiati.test' },
        { id: 'a2', email: 'two@wasiati.test' },
      ],
      sendEmail,
    );

    await submit(svc);
    expect(sendEmail.mock.calls.map((c) => c[0])).toEqual(['one@wasiati.test', 'two@wasiati.test']);
  });
});
