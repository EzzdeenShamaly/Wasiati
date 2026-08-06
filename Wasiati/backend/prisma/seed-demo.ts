import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

/**
 * Seeds a rich demo environment so the app has realistic data to click through:
 *   - demo@wasiati.test / DemoPass12345 — a NON-admin user COMPED to ULTIMATE
 *     (so the demo shows full access without paying, like a real comped account)
 *   - a sample will with Sharia shares, a witness, and a confirmed trustee
 *   - a burial estimate
 *   - a pending death claim (so the admin death-claim queue has an item)
 *
 * Run:  pnpm seed:demo   (after seed:admin + seed:pricing)
 */
async function main() {
  // Refuse to run against production: this plants a publicly-documented password on a
  // comped-ULTIMATE account. An operator replaying bootstrap steps at a prod DATABASE_URL
  // would otherwise create a working full-access login.
  if (process.env.NODE_ENV === 'production') {
    throw new Error('seed-demo must never run in production (it creates a known-credential account).');
  }

  const passwordHash = await bcrypt.hash('DemoPass12345', 12);

  // The demo account is ID-VERIFIED (spec §3: identity verification is required
  // before any will can seal) and carries a phone so the delete/unpublish step-up
  // OTP flow is exercisable end-to-end (with OTP_DEV_ECHO=true in dev).
  const demo = await prisma.user.upsert({
    where: { email: 'demo@wasiati.test' },
    update: {
      compTier: 'ULTIMATE',
      compExpiresAt: null,
      emailVerified: true,
      idVerificationStatus: 'VERIFIED',
      phone: '+15551230000',
    },
    create: {
      email: 'demo@wasiati.test',
      passwordHash,
      region: 'US',
      emailVerified: true,
      idVerificationStatus: 'VERIFIED', // may seal wills without a live KYC round-trip
      phone: '+15551230000', // step-up OTP destination
      compTier: 'ULTIMATE', // comped demo access — no payment needed
    },
  });

  // Avoid piling up duplicate demo wills on repeated runs.
  const existing = await prisma.will.findFirst({ where: { ownerId: demo.id } });
  if (!existing) {
    const will = await prisma.will.create({
      data: {
        ownerId: demo.id,
        tier: 'STANDARD',
        locked: false,
        disclaimerVersion: 'demo',
        disclaimerAcceptedAt: new Date(),
        shariaShares: {
          create: [
            { heirRelation: 'SPOUSE', heirName: 'Aisha', sharePercent: 12.5 },
            { heirRelation: 'SON', heirName: 'Yusuf', sharePercent: 58.33 },
            { heirRelation: 'DAUGHTER', heirName: 'Maryam', sharePercent: 29.17 },
          ],
        },
        bequests: { create: [{ beneficiaryName: 'Local mosque', sharePercent: 10, notes: 'Sadaqah jariyah' }] },
        witnesses: { create: [{ fullName: 'Omar Ali', phone: '+15551230001', status: 'PENDING' }] },
        trustees: { create: [{ fullName: 'Bilal Khan', phone: '+15551230002', status: 'CONFIRMED', confirmedAt: new Date() }] },
      },
    });

    await prisma.deathClaim.create({
      data: {
        willId: will.id,
        submittedByName: 'Bilal Khan',
        submittedByPhone: '+15551230002',
        certificateFileUrl: 'https://example.com/death-certificate.pdf',
        status: 'SUBMITTED',
      },
    });
  }

  // A SEALED will as well, so the demo can show the executed document — the
  // gold rosette footer ("Sealed & witnessed via Wasiati"), the script
  // signatures with their dates, and the completion certificate all render only
  // on a sealed will (a draft must not look executed), and until this existed
  // the demo account had no way to see any of it ("stamp at the bottom
  // missing" — owner, 27 Jul 2026). Data mirrors the DV2.1 prototype's demo
  // will (W-4821): the estate rows, the 12.5/58.33/29.17 split, two signed
  // witnesses, and a trustee still pending their code.
  const sealed = await prisma.will.findFirst({ where: { ownerId: demo.id, status: 'SEALED' } });
  if (!sealed) {
    const sealDate = new Date('2026-05-03T10:00:00Z');
    await prisma.will.create({
      data: {
        ownerId: demo.id,
        tier: 'PREMIUM',
        locked: true,
        status: 'SEALED',
        sealedAt: sealDate,
        publishedAt: sealDate,
        signedAt: sealDate,
        signedIp: '203.0.113.7',
        requiredWitnesses: 2,
        disclaimerVersion: 'demo',
        disclaimerAcceptedAt: new Date('2026-05-01T09:00:00Z'),
        personalMessage:
          'Yusuf, Maryam — look after your mother. Forgive me my shortcomings, and keep me in your du‘a.',
        funeralWishes: { sunnah: true, simple: true, local: true, azaa: true },
        shariaShares: {
          create: [
            { heirRelation: 'WIFE', heirName: 'Aisha', sharePercent: 12.5 },
            { heirRelation: 'SON', heirName: 'Yusuf', sharePercent: 58.33 },
            { heirRelation: 'DAUGHTER', heirName: 'Maryam', sharePercent: 29.17 },
          ],
        },
        bequests: { create: [{ beneficiaryName: 'Local mosque', sharePercent: 6, notes: 'Sadaqah jariyah' }] },
        witnesses: {
          create: [
            {
              fullName: 'Khalid Al-Dosari',
              phone: '+15551230003',
              status: 'SIGNED',
              signedAt: sealDate,
              idMatchStatus: 'MATCHED',
              ipAddress: '198.51.100.22',
              userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) Safari/605',
            },
            {
              fullName: 'Omar Basha',
              phone: '+15551230004',
              status: 'SIGNED',
              signedAt: sealDate,
              idMatchStatus: 'MATCHED',
              ipAddress: '198.51.100.23',
              userAgent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/120',
            },
          ],
        },
        trustees: {
          create: [
            { fullName: 'Fatima Al-Rashid', phone: '+15551230005', email: 'fatima.r@example.com', status: 'PENDING' },
          ],
        },
        assets: {
          create: [
            { type: 'BANK_ACCOUNT', label: 'Current account', institution: 'Al Rajhi', estimatedValue: 184000, currency: 'USD' },
            { type: 'REAL_ESTATE', label: 'Villa — Al Narjis district', estimatedValue: 2100000, currency: 'USD' },
            { type: 'SHARES', label: 'Tadawul portfolio', estimatedValue: 96400, currency: 'USD' },
            { type: 'LIABILITY', label: 'Home financing — Murabaha', estimatedValue: 420000, currency: 'USD' },
            { type: 'LIABILITY', label: 'Car financing — Ijara', estimatedValue: 58000, currency: 'USD' },
          ],
        },
      },
    });
  }

  await prisma.burialEstimateRequest.create({
    data: {
      userId: demo.id,
      region: 'US',
      city: 'Austin',
      baseAmount: 8000,
      currency: 'USD',
      baseYear: 2026,
      inflationRatePercent: 4,
      projectionYears: 10,
      projectedAmount: 11842,
      status: 'ESTIMATED',
    },
  });

  console.log('Demo seeded: demo@wasiati.test / DemoPass12345 (comped ULTIMATE) + a draft will, a SEALED will (rosette, signatures, certificate), burial estimate, and a pending death claim.');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
