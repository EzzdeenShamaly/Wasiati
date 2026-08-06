import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { Region, AssetType } from '@prisma/client';

/**
 * Returns the asset-type catalog the frontend should show, filtered to the
 * generic types plus whatever's relevant for the user's region. This is the
 * single source of truth — both web and iOS call GET /assets/types/:region
 * and render whatever comes back, so adding a new local account type later
 * only requires a backend change, not a client release.
 */
const REGION_TYPES: Record<Region, AssetType[]> = {
  CA: ['CA_RRSP', 'CA_TFSA', 'CA_RESP', 'CA_RRIF'],
  US: ['US_401K', 'US_IRA', 'US_ROTH_IRA', 'US_529_PLAN'],
  KSA: ['KSA_END_OF_SERVICE_BENEFITS', 'KSA_GOSI_PENSION'],
};

/**
 * Everything not claimed by a region is generic and offered everywhere. DERIVED
 * from the enum, not hand-listed: a hand-kept copy silently dropped CASH, SHARES,
 * GOLD, CRYPTO, PENSION and LIABILITY — which would have hidden the zakat-base
 * types (see ZakatService) and the debts that must be settled before the fara'id
 * shares. Deriving makes a forgotten new member impossible; OTHER is kept last
 * because it's the catch-all the clients render at the bottom.
 */
const REGION_SPECIFIC = new Set<AssetType>(Object.values(REGION_TYPES).flat());
const GENERIC_TYPES: AssetType[] = [
  ...Object.values(AssetType).filter((t) => !REGION_SPECIFIC.has(t) && t !== AssetType.OTHER),
  AssetType.OTHER,
];

@Injectable()
export class AssetsService {
  constructor(private prisma: PrismaService) {}

  getAssetTypesForRegion(region: Region): AssetType[] {
    return [...GENERIC_TYPES, ...REGION_TYPES[region]];
  }

  /** Confirms the will belongs to the caller before any read/write. NotFound (not
   *  Forbidden) so we never disclose that another user's will exists. */
  private async assertWillOwner(willId: string, ownerId: string) {
    const will = await this.prisma.will.findUnique({ where: { id: willId }, select: { ownerId: true } });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
  }

  async add(
    willId: string,
    ownerId: string,
    data: {
      type: AssetType;
      label: string;
      institution?: string;
      estimatedValue?: number;
      currency?: string;
      notes?: string;
      contactPhone?: string;
      contactEmail?: string;
      accountRef?: string;
    },
  ) {
    await this.assertWillOwner(willId, ownerId);
    return this.prisma.asset.create({ data: { willId, ...data } });
  }

  async listForWill(willId: string, ownerId: string) {
    await this.assertWillOwner(willId, ownerId);
    return this.prisma.asset.findMany({ where: { willId } });
  }

  async remove(assetId: string, ownerId: string) {
    // Resolve the asset's owning will and verify ownership before deleting.
    const asset = await this.prisma.asset.findUnique({
      where: { id: assetId },
      select: { id: true, will: { select: { ownerId: true } } },
    });
    if (!asset || asset.will.ownerId !== ownerId) throw new NotFoundException('Asset not found.');
    return this.prisma.asset.delete({ where: { id: assetId } });
  }

  async update(
    assetId: string,
    ownerId: string,
    data: Partial<{
      type: AssetType;
      label: string;
      institution: string;
      estimatedValue: number;
      currency: string;
      notes: string;
      contactPhone: string;
      contactEmail: string;
      accountRef: string;
    }>,
  ) {
    // Same ownership walk as remove(): asset -> will -> owner, NotFound otherwise.
    const asset = await this.prisma.asset.findUnique({
      where: { id: assetId },
      select: { id: true, will: { select: { ownerId: true } } },
    });
    if (!asset || asset.will.ownerId !== ownerId) throw new NotFoundException('Asset not found.');
    return this.prisma.asset.update({ where: { id: assetId }, data });
  }

  /** The will's inventory as a CSV (Excel-openable). Owner-scoped. */
  async exportCsv(willId: string, ownerId: string): Promise<string> {
    const rows = await this.listForWill(willId, ownerId);
    return assetsToCsv(rows);
  }
}

/**
 * Serialises inventory rows to CSV. Every cell is quoted; embedded quotes are
 * doubled (RFC 4180). Cells starting with = + - @ get a leading apostrophe so a
 * hostile label can never execute as a formula when the file opens in Excel.
 */
export function assetsToCsv(
  rows: {
    type: string;
    label: string;
    institution?: string | null;
    contactPhone?: string | null;
    contactEmail?: string | null;
    accountRef?: string | null;
    estimatedValue?: unknown;
    currency?: string | null;
    notes?: string | null;
  }[],
): string {
  const cell = (v: unknown): string => {
    let s = v == null ? '' : String(v);
    if (/^[=+\-@]/.test(s)) s = `'${s}`; // formula-injection guard
    return `"${s.replace(/"/g, '""')}"`;
  };
  const header = ['Kind', 'Type', 'Name', 'Held with', 'Phone', 'Email', 'Account / IBAN', 'Currency', 'Estimated value', 'Notes'];
  const lines = [header.map(cell).join(',')];
  for (const r of rows) {
    lines.push(
      [
        r.type === 'LIABILITY' ? 'Loan / liability' : 'Asset',
        r.type,
        r.label,
        r.institution,
        r.contactPhone,
        r.contactEmail,
        r.accountRef,
        r.currency,
        r.estimatedValue == null ? '' : String(r.estimatedValue),
        r.notes,
      ]
        .map(cell)
        .join(','),
    );
  }
  return `${lines.join('\r\n')}\r\n`;
}
