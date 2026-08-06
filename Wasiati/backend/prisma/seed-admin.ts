import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

/**
 * Creates (or promotes) a single admin user from env vars. Run with:
 *   ADMIN_EMAIL=you@wasiati.com ADMIN_PASSWORD=... npx ts-node prisma/seed-admin.ts
 *
 * There's deliberately no API endpoint to grant ADMIN role — that has to stay
 * a manual, out-of-band operation (this script, or a direct DB update) so a
 * compromised user account can never self-promote to admin over the API.
 */
async function main() {
  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;
  const region = (process.env.ADMIN_REGION as 'KSA' | 'CA' | 'US') ?? 'US';

  if (!email || !password) {
    throw new Error('Set ADMIN_EMAIL and ADMIN_PASSWORD env vars before running this script.');
  }
  if (password.length < 12) {
    throw new Error('Admin password must be at least 12 characters.');
  }

  const passwordHash = await bcrypt.hash(password, 12);

  const user = await prisma.user.upsert({
    where: { email },
    update: { role: 'ADMIN' },
    create: { email, passwordHash, region, role: 'ADMIN' },
  });

  console.log(`Admin user ready: ${user.email} (role: ${user.role})`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
