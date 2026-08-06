import { IdentityService } from './identity.service';
import { Prisma } from '@prisma/client';

/**
 * A captured, correctly-signed Sumsub "GREEN" webhook must not be replayable later to
 * flip a KYC-revoked user back to VERIFIED. Idempotency is keyed on a hash of the raw
 * body, so a verbatim replay is a no-op.
 */
function makeService(opts: { seen?: Set<string> } = {}) {
  const seen = opts.seen ?? new Set<string>();
  const updates: any[] = [];

  const provider = {
    name: 'SUMSUB',
    // Signature "verified" for the test; returns a fixed mapping.
    parseWebhook: (raw: Buffer) => ({
      userId: 'user-1',
      status: JSON.parse(raw.toString()).status as 'VERIFIED' | 'PENDING' | 'REJECTED',
      providerRef: 'appl-1',
    }),
  } as any;

  const prisma: any = {
    processedIdentityEvent: {
      create: async ({ data }: any) => {
        if (seen.has(data.id)) {
          throw new Prisma.PrismaClientKnownRequestError('dup', { code: 'P2002', clientVersion: 't' });
        }
        seen.add(data.id);
        return data;
      },
    },
    user: {
      updateMany: async ({ data }: any) => {
        updates.push(data);
        return { count: 1 };
      },
    },
  };

  return { svc: new IdentityService(prisma, provider), updates, seen };
}

describe('identity webhook replay protection', () => {
  const body = (status: string) => Buffer.from(JSON.stringify({ status, applicantId: 'appl-1' }));

  it('processes a signed webhook once', async () => {
    const { svc, updates } = makeService();
    const res = await svc.handleWebhook(body('VERIFIED'), 'sig', 'HMAC_SHA256_HEX');
    expect(res).toEqual({ received: true });
    expect(updates).toHaveLength(1);
  });

  it('IGNORES a verbatim replay — the second identical body is a no-op', async () => {
    const { svc, updates } = makeService();
    await svc.handleWebhook(body('VERIFIED'), 'sig');
    const replay = await svc.handleWebhook(body('VERIFIED'), 'sig'); // same bytes

    expect(replay).toEqual({ received: true, duplicate: true });
    expect(updates).toHaveLength(1); // status was NOT written a second time
  });

  it('a genuinely different event (different body) still processes', async () => {
    const { svc, updates } = makeService();
    await svc.handleWebhook(body('REJECTED'), 'sig');
    await svc.handleWebhook(body('VERIFIED'), 'sig'); // different bytes -> different hash
    expect(updates).toHaveLength(2);
  });
});
