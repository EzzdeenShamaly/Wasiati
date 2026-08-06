import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { createHash, randomInt } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';

/** How many codes a set contains. Ten is the industry convention and prints on one card. */
export const RECOVERY_CODE_COUNT = 10;
/** Below this, the UI should nag. Running out silently is the failure mode that matters. */
export const RECOVERY_CODES_LOW_WATER = 3;

/**
 * Crockford-style base32, minus the letters that get misread off a printed card: no I, L,
 * O, U. A recovery code is written down and typed back weeks later by someone under
 * stress, so every ambiguous glyph is a support ticket.
 */
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const GROUPS = 3;
const GROUP_LEN = 4;

/**
 * Single-use backup codes for MFA.
 *
 * These exist because the ladder makes an authenticator app the preferred second factor,
 * and an authenticator lives on exactly one device. On a will platform, "I lost my phone"
 * must not mean "my family cannot reach my will": there is no identity-proofing path a
 * support human could take that would not re-create the impersonation risk MFA is there to
 * prevent. Ten offline codes are free, need no signal, and fit a product that already asks
 * people to keep documents somewhere safe.
 *
 * The rule they enable: never let an account hold only ONE route to itself.
 */
@Injectable()
export class RecoveryCodesService {
  private readonly logger = new Logger(RecoveryCodesService.name);

  constructor(private prisma: PrismaService) {}

  /**
   * Normalises before hashing so the stored form does not depend on how it was typed.
   * People re-type these from paper: lower case, missing dashes and stray spaces are all
   * the same code, and rejecting them would look like a wrong code rather than a format.
   */
  static normalize(code: string): string {
    return (code ?? '').toUpperCase().replace(/[^0-9A-Z]/g, '');
  }

  private hash(code: string): string {
    return createHash('sha256').update(RecoveryCodesService.normalize(code)).digest('hex');
  }

  /** `X7K2-9QMD-4TVB` — grouped for legibility; the dashes are cosmetic. */
  private generateOne(): string {
    const groups: string[] = [];
    for (let g = 0; g < GROUPS; g++) {
      let s = '';
      // randomInt, not Math.random: these are credentials that bypass the second factor.
      for (let i = 0; i < GROUP_LEN; i++) s += ALPHABET[randomInt(0, ALPHABET.length)];
      groups.push(s);
    }
    return groups.join('-');
  }

  /**
   * Issues a fresh set and INVALIDATES every previous code.
   *
   * Replacing rather than adding is deliberate: a user who regenerates because they think
   * their codes leaked must actually have retired the leaked ones. Returns the plaintext,
   * which is the only time it exists anywhere.
   */
  async regenerate(userId: string): Promise<{ codes: string[] }> {
    const codes = Array.from({ length: RECOVERY_CODE_COUNT }, () => this.generateOne());
    await this.prisma.$transaction(async (tx) => {
      await tx.recoveryCode.deleteMany({ where: { userId } });
      await tx.recoveryCode.createMany({
        data: codes.map((c) => ({ userId, codeHash: this.hash(c) })),
      });
    });
    this.logger.log(`Issued ${codes.length} recovery codes for user ${userId} (previous set invalidated).`);
    return { codes };
  }

  /** How many are left, for the security screen and the low-water nag. */
  async status(userId: string): Promise<{ remaining: number; total: number; low: boolean }> {
    const [remaining, total] = await Promise.all([
      this.prisma.recoveryCode.count({ where: { userId, usedAt: null } }),
      this.prisma.recoveryCode.count({ where: { userId } }),
    ]);
    return { remaining, total, low: total > 0 && remaining <= RECOVERY_CODES_LOW_WATER };
  }

  /**
   * Spends a code, if it is one of this user's unused ones.
   *
   * Scoped to the userId as well as the hash: the hash is unique globally, but matching on
   * it alone would let a code from one account satisfy a challenge for another. The update
   * is CONDITIONAL on usedAt still being null, so two simultaneous attempts with the same
   * code cannot both succeed — single-use has to hold under a race, not just in sequence.
   */
  async consume(userId: string, code: string): Promise<boolean> {
    const normalized = RecoveryCodesService.normalize(code);
    // Length check first: a 6-digit TOTP arrives here too, and there is no point hashing
    // and querying for something that cannot be a recovery code.
    if (normalized.length !== GROUPS * GROUP_LEN) return false;

    const { count } = await this.prisma.recoveryCode.updateMany({
      where: { userId, codeHash: this.hash(normalized), usedAt: null },
      data: { usedAt: new Date() },
    });
    if (count === 0) return false;

    const { remaining } = await this.status(userId);
    // Deliberately loud. A recovery code the owner did not use is how they find out
    // someone else is in their account, and running out unnoticed is a lockout waiting.
    this.logger.warn(`Recovery code SPENT for user ${userId}; ${remaining} remaining.`);
    return true;
  }

  /** Guards a flow that must not proceed without a usable code left. */
  async assertHasCodes(userId: string): Promise<void> {
    const { remaining } = await this.status(userId);
    if (remaining === 0) throw new UnauthorizedException('No recovery codes remain on this account.');
  }
}
