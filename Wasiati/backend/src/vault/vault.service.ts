import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, SubscriptionTier } from '@prisma/client';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { EntitlementsService } from '../entitlements/entitlements.service';

/** Standard's vault is capped (spec §2/§5); Premium and above are unlimited. */
const STANDARD_VAULT_LIMIT = 5;

@Injectable()
export class VaultService {
  constructor(
    private prisma: PrismaService,
    private entitlements: EntitlementsService,
  ) {}

  /** The item ceiling for a user's plan: 5 for Standard, unlimited for Premium+/admin. */
  private async itemLimit(userId: string): Promise<number> {
    const ent = await this.entitlements.resolve(userId);
    const premiumPlus =
      ent.isAdmin || ent.tier === SubscriptionTier.PREMIUM || ent.tier === SubscriptionTier.ULTIMATE;
    return premiumPlus ? Infinity : STANDARD_VAULT_LIMIT;
  }

  /** Ensures a vault row exists for this user, with a random KDF salt. */
  private async ensureVault(userId: string) {
    return this.prisma.vault.upsert({
      where: { userId },
      update: {},
      create: { userId, kdfSalt: randomBytes(16).toString('base64') },
    });
  }

  /**
   * The client's PBKDF2 salt. Set once per vault and never changed (changing it would
   * orphan every already-encrypted item). Backfills an existing salt-less vault
   * race-safely: only the writer whose conditional update wins sets it.
   */
  async getKdfSalt(userId: string): Promise<{ salt: string; verifier: string | null; hasItems: boolean }> {
    const vault = await this.ensureVault(userId);
    // Whether anything is stored decides what the client can check against when no verifier
    // exists yet: an existing item proves the KEK, an empty vault has nothing to prove it.
    const hasItems = (await this.prisma.vaultItem.count({ where: { vaultId: vault.id } })) > 0;
    if (vault.kdfSalt) return { salt: vault.kdfSalt, verifier: vault.kekVerifier, hasItems };

    const salt = randomBytes(16).toString('base64');
    await this.prisma.vault.updateMany({ where: { id: vault.id, kdfSalt: null }, data: { kdfSalt: salt } });
    const fresh = await this.prisma.vault.findUnique({
      where: { id: vault.id },
      select: { kdfSalt: true, kekVerifier: true },
    });
    return { salt: fresh?.kdfSalt ?? salt, verifier: fresh?.kekVerifier ?? null, hasItems };
  }

  /**
   * Records the vault's passphrase check, ONCE.
   *
   * WRITE-ONCE, enforced in the WHERE rather than by reading first. If a second write could
   * replace it, a typo would not merely fail to unlock — it would overwrite the verifier and
   * lock the REAL passphrase out of the user's own vault, turning a recoverable mistake into
   * the exact permanent loss this column exists to prevent. A conditional update makes that
   * impossible rather than unlikely.
   *
   * The blob is opaque here by design: the server has no passphrase, no KEK and no way to
   * check it. Trusting the client is not a weakness in this direction — a caller who wanted
   * to write a junk verifier could equally just delete their own items.
   */
  async setKekVerifier(userId: string, verifier: string): Promise<{ stored: boolean }> {
    if (typeof verifier !== 'string' || verifier.length < 16 || verifier.length > 512) {
      throw new BadRequestException('Invalid vault verifier.');
    }
    const vault = await this.ensureVault(userId);
    const { count } = await this.prisma.vault.updateMany({
      where: { id: vault.id, kekVerifier: null },
      data: { kekVerifier: verifier },
    });
    // Not an error when it loses: another device got there first, and the existing verifier
    // is the one that counts. The client re-reads and checks against it.
    return { stored: count === 1 };
  }

  /**
   * ciphertext and encryptedDataKey arrive already encrypted client-side
   * (AES-256 for the data, RSA-4096 for the per-item key). The server never
   * sees plaintext and has no way to decrypt this on its own.
   */
  async addItem(userId: string, label: string, ciphertext: string, encryptedDataKey: string) {
    const vault = await this.ensureVault(userId);
    const limit = await this.itemLimit(userId);
    if (!Number.isFinite(limit)) {
      return this.prisma.vaultItem.create({
        data: { vaultId: vault.id, label, ciphertext, encryptedDataKey },
      });
    }
    // Enforce the per-plan cap ATOMICALLY: Serializable makes two concurrent adds at the
    // limit conflict rather than both committing (same read-count-write race we close on
    // the bequest cap and upload quota).
    return this.prisma.$transaction(
      async (tx) => {
        const count = await tx.vaultItem.count({ where: { vaultId: vault.id } });
        if (count >= limit) {
          throw new BadRequestException(
            `Your plan includes ${limit} vault items. Upgrade to Premium for an unlimited vault.`,
          );
        }
        return tx.vaultItem.create({ data: { vaultId: vault.id, label, ciphertext, encryptedDataKey } });
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  }

  async listItems(userId: string) {
    const vault = await this.prisma.vault.findUnique({ where: { userId }, include: { items: true } });
    return vault?.items ?? [];
  }

  async deleteItem(itemId: string, userId: string) {
    // Only allow deleting an item that lives in the caller's own vault.
    const item = await this.prisma.vaultItem.findUnique({
      where: { id: itemId },
      select: { id: true, vault: { select: { userId: true } } },
    });
    if (!item || item.vault.userId !== userId) throw new NotFoundException('Vault item not found.');
    return this.prisma.vaultItem.delete({ where: { id: itemId } });
  }
}
