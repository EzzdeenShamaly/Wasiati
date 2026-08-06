import { BadRequestException } from '@nestjs/common';
import { WitnessesService } from './witnesses.service';
import { TrusteesService } from '../trustees/trustees.service';

/**
 * An executed will's attestation page must not change after execution.
 *
 * WillDocumentService renders the witnesses and the trustee in one "Witnesses & trustee"
 * block, each by name, role and signing date; it counts the confirmed witnesses into the
 * header and the sealed footer ("2 witnesses confirmed"); and it lists them again on the
 * signature certificate. Yet addWitness/addTrustee checked ownership and stopped, and
 * confirmSignature/confirm checked the one-time code and stopped. So a sealed will could
 * grow a witness, and a stale invitation could still be answered — putting a new name, with
 * a date LATER than the seal, onto a document that had already been executed.
 *
 * HeirContactsService.assertEditable was already doing this for the roster it owns. These
 * four were the adjacent paths that never picked it up.
 */
const CODE = '123456';

function harness(willStatus: string) {
  const prisma: any = {
    will: { findUnique: jest.fn().mockResolvedValue({ ownerId: 'owner1', status: willStatus }) },
    witness: {
      create: jest.fn(async ({ data }: any) => ({ id: 'wit1', ...data })),
      findUnique: jest.fn().mockResolvedValue({
        id: 'wit1',
        willId: 'will1',
        fullName: 'Khalid Al-Rashid',
        phone: '+966555000111',
      }),
      update: jest.fn(async ({ data }: any) => ({ id: 'wit1', ...data })),
    },
    trustee: {
      create: jest.fn(async ({ data }: any) => ({ id: 'tr1', ...data })),
      findUnique: jest.fn().mockResolvedValue({
        id: 'tr1',
        willId: 'will1',
        fullName: 'Fatima Al-Rashid',
        phone: '+966555000222',
      }),
      update: jest.fn(async ({ data }: any) => ({ id: 'tr1', ...data })),
    },
  };
  const notifications: any = { sendSms: jest.fn().mockResolvedValue(true), sendEmail: jest.fn().mockResolvedValue(true) };
  // A VALID code throughout: the point is that a correct code is not enough on a sealed
  // will. If the guard were gone these would sail past the OTP and record the signature.
  const otp: any = { issue: jest.fn(), verify: jest.fn().mockResolvedValue(true) };
  const config: any = { get: () => 'http://localhost:3000' };
  const redis: any = { incrWithTtl: async () => 1 };
  const wills: any = { recomputeAfterWitness: jest.fn() };
  return {
    prisma,
    witnesses: new WitnessesService(prisma, notifications, otp, wills, config, redis),
    trustees: new TrusteesService(prisma, otp, notifications, config, redis),
  };
}

describe('a SEALED will’s roster is frozen', () => {
  it('REFUSES to add a witness to a sealed will', async () => {
    const { witnesses, prisma } = harness('SEALED');
    await expect(witnesses.addWitness('will1', 'owner1', 'Omar', '+966555000333')).rejects.toThrow(
      /has been sealed/i,
    );
    expect(prisma.witness.create).not.toHaveBeenCalled();
  });

  it('REFUSES to add a trustee to a sealed will', async () => {
    const { trustees, prisma } = harness('SEALED');
    await expect(trustees.addTrustee('will1', 'owner1', 'Noura', '+966555000444')).rejects.toThrow(
      /has been sealed/i,
    );
    expect(prisma.trustee.create).not.toHaveBeenCalled();
  });

  // The stale-invitation case: the will sealed on two witnesses, and the third — whose
  // link was sitting in their inbox all along — signs a week later. Their name and a
  // post-seal date would appear on the executed attestation page.
  it('REFUSES a witness signature on a sealed will, even with a VALID code', async () => {
    const { witnesses, prisma } = harness('SEALED');
    await expect(
      witnesses.confirmSignature('wit1', CODE, 'sig', 'Khalid Al-Rashid', '1.2.3.4'),
    ).rejects.toThrow(/has been sealed/i);
    expect(prisma.witness.update).not.toHaveBeenCalled();
  });

  it('REFUSES a trustee confirmation on a sealed will, even with a VALID code', async () => {
    const { trustees, prisma } = harness('SEALED');
    await expect(trustees.confirm('tr1', CODE, '1.2.3.4')).rejects.toThrow(/has been sealed/i);
    expect(prisma.trustee.update).not.toHaveBeenCalled();
  });

  // Retained history of a will that was once executed. History that can still be written
  // to is not history.
  it('freezes a SUPERSEDED will too, and says why it is different', async () => {
    const { witnesses, trustees } = harness('SUPERSEDED');
    await expect(witnesses.addWitness('will1', 'owner1', 'Omar', '+966555000333')).rejects.toThrow(
      /replaced by a newer sealed version/i,
    );
    await expect(trustees.confirm('tr1', CODE)).rejects.toThrow(/replaced by a newer sealed version/i);
  });

  it('is a BadRequest, not a 500 — the owner is told, not shown a crash', async () => {
    const { witnesses } = harness('SEALED');
    await expect(witnesses.addWitness('will1', 'owner1', 'Omar', '+966555000333')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});

/**
 * The other half of the trade, and the reason this guard is NOT HeirContactsService's
 * "anything not DRAFT is frozen".
 *
 * Witnessing and trustee confirmation happen ON a locked, SIGNED will — that is what they
 * are for. And there is no route to delete a witness or a trustee, so refusing to ADD one
 * at SIGNED would strand an owner whose witness has an unreachable number with no way to
 * replace the row: the exact silent dead end that notifyWitnessInvited's `notified` flag
 * was added to surface. The roster stays open right up to execution.
 */
describe('...but stays open until then', () => {
  for (const status of ['DRAFT', 'SIGNED', 'WITNESSED']) {
    it(`still accepts a witness and a trustee on a ${status} will`, async () => {
      const { witnesses, trustees } = harness(status);
      await expect(witnesses.addWitness('will1', 'owner1', 'Omar', '+966555000333')).resolves.toBeDefined();
      await expect(trustees.addTrustee('will1', 'owner1', 'Noura', '+966555000444')).resolves.toBeDefined();
    });

    it(`still accepts a witness signature and a trustee confirmation on a ${status} will`, async () => {
      const { witnesses, trustees } = harness(status);
      await expect(
        witnesses.confirmSignature('wit1', CODE, 'sig', 'Khalid Al-Rashid', '1.2.3.4'),
      ).resolves.toMatchObject({ status: 'SIGNED' });
      await expect(trustees.confirm('tr1', CODE)).resolves.toMatchObject({ status: 'CONFIRMED' });
    });
  }
});

/**
 * WHERE the check sits in confirmSignature/confirm is itself a decision.
 *
 * Both routes are unauthenticated, and the witness/trustee id travels in an invitation
 * link — the kind of thing that gets forwarded into a family group chat. The file is
 * careful never to tell an unproven caller that an id is real (see the no-echo rules on
 * sendSigningCode). Running the seal check AFTER the OTP keeps that property exactly:
 * only someone who has proven possession of the roster row's phone learns anything.
 */
describe('the seal check discloses nothing to a caller who cannot prove the phone', () => {
  it('a WRONG code on a sealed will still says only "invalid or expired"', async () => {
    const prisma: any = {
      will: { findUnique: jest.fn().mockResolvedValue({ ownerId: 'owner1', status: 'SEALED' }) },
      witness: {
        findUnique: jest.fn().mockResolvedValue({ id: 'wit1', willId: 'will1', fullName: 'Khalid', phone: '+966555000111' }),
        update: jest.fn(),
      },
    };
    const otp: any = { issue: jest.fn(), verify: jest.fn().mockResolvedValue(false) };
    const svc = new WitnessesService(
      prisma,
      { sendSms: jest.fn(), sendEmail: jest.fn() } as any,
      otp,
      { recomputeAfterWitness: jest.fn() } as any,
      { get: () => 'http://localhost:3000' } as any,
      { incrWithTtl: async () => 1 } as any,
    );
    await expect(svc.confirmSignature('wit1', 'wrong', 'sig', 'Khalid', '1.2.3.4')).rejects.toThrow(
      /invalid or expired/i,
    );
    // Nothing about the will's state leaked, and the will was never even looked up.
    expect(prisma.will.findUnique).not.toHaveBeenCalled();
  });
});
