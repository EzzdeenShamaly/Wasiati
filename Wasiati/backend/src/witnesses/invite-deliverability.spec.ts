import { WitnessesService } from './witnesses.service';
import { TrusteesService } from '../trustees/trustees.service';

/**
 * A roster invite that reached NOBODY must not look like one that was delivered.
 *
 * `email` is optional on both the witness and trustee rosters while `phone` is required.
 * sendSms used to return void and succeeded silently when Twilio was unconfigured (or when
 * a carrier rejected the number), so a phone-only witness could receive nothing at all
 * while the owner saw a clean success. They then wait for a confirmation that was never
 * requested — the will never reaches its witness quorum, and never seals. The owner is the
 * only person who can fix it, and they cannot act on a failure they are never shown.
 */
function harness(opts: { smsOk: boolean; emailOk?: boolean }) {
  const notifications: any = {
    sendSms: jest.fn().mockResolvedValue(opts.smsOk),
    sendEmail: jest.fn().mockResolvedValue(opts.emailOk ?? true),
  };
  const config: any = { get: () => 'http://localhost:3000' };
  const row = { id: 'w1', willId: 'will1', fullName: 'Khalid', phone: '+966555000111', email: null as string | null };
  const prisma: any = {
    // `status` is read too: a roster row cannot be added to an EXECUTED will, because the
    // witnesses and trustee are rendered on the sealed document (common/will-executed.ts).
    // DRAFT here — the subject of this suite is delivery, not the freeze.
    will: { findUnique: jest.fn().mockResolvedValue({ ownerId: 'owner1', status: 'DRAFT' }) },
    witness: { create: jest.fn(async ({ data }: any) => ({ ...row, ...data })) },
    trustee: { create: jest.fn(async ({ data }: any) => ({ ...row, ...data })) },
  };
  return { notifications, config, prisma };
}

describe('roster invites report whether anyone was actually reached', () => {
  it('a phone-only witness whose SMS never dispatched comes back notified:false', async () => {
    const { notifications, config, prisma } = harness({ smsOk: false });
    const svc = new WitnessesService(prisma, notifications, {} as any, {} as any, config, { incrWithTtl: async () => 1 } as any);
    const out: any = await svc.addWitness('will1', 'owner1', 'Khalid', '+966555000111');
    expect(out.notified).toBe(false);
    expect(notifications.sendEmail).not.toHaveBeenCalled(); // no address to fall back to
  });

  it('the witness is still recorded — delivery must never block the roster', async () => {
    const { notifications, config, prisma } = harness({ smsOk: false });
    const svc = new WitnessesService(prisma, notifications, {} as any, {} as any, config, { incrWithTtl: async () => 1 } as any);
    const out: any = await svc.addWitness('will1', 'owner1', 'Khalid', '+966555000111');
    expect(out.id).toBeDefined();
    expect(prisma.witness.create).toHaveBeenCalled();
  });

  it('email rescues a failed SMS — reached by ANY channel counts', async () => {
    const { notifications, config, prisma } = harness({ smsOk: false, emailOk: true });
    const svc = new WitnessesService(prisma, notifications, {} as any, {} as any, config, { incrWithTtl: async () => 1 } as any);
    const out: any = await svc.addWitness('will1', 'owner1', 'Khalid', '+966555000111', 'k@example.com');
    expect(out.notified).toBe(true);
  });

  it('both channels failing is reported, not swallowed', async () => {
    const { notifications, config, prisma } = harness({ smsOk: false, emailOk: false });
    const svc = new WitnessesService(prisma, notifications, {} as any, {} as any, config, { incrWithTtl: async () => 1 } as any);
    const out: any = await svc.addWitness('will1', 'owner1', 'Khalid', '+966555000111', 'k@example.com');
    expect(out.notified).toBe(false);
  });

  it('a thrown SMS is caught and still reported as undelivered', async () => {
    const { notifications, config, prisma } = harness({ smsOk: true });
    notifications.sendSms.mockRejectedValue(new Error('carrier rejected'));
    const svc = new WitnessesService(prisma, notifications, {} as any, {} as any, config, { incrWithTtl: async () => 1 } as any);
    const out: any = await svc.addWitness('will1', 'owner1', 'Khalid', '+966555000111');
    expect(out.notified).toBe(false);
  });

  it('the trustee path behaves identically — release is gated on them confirming', async () => {
    const { notifications, config, prisma } = harness({ smsOk: false });
    const svc = new TrusteesService(prisma, {} as any, notifications, config, { incrWithTtl: async () => 1 } as any);
    const out: any = await svc.addTrustee('will1', 'owner1', 'Fatima', '+966555000222');
    expect(out.notified).toBe(false);
  });

  it('a delivered invite reports true, so the flag means something', async () => {
    const { notifications, config, prisma } = harness({ smsOk: true });
    const svc = new WitnessesService(prisma, notifications, {} as any, {} as any, config, { incrWithTtl: async () => 1 } as any);
    const out: any = await svc.addWitness('will1', 'owner1', 'Khalid', '+966555000111');
    expect(out.notified).toBe(true);
  });
});
