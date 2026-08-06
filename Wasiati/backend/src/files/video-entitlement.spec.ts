import { ForbiddenException } from '@nestjs/common';
import { FilesService } from './files.service';

/**
 * Video legacy messages are sold as a Premium feature, so the server has to be the
 * thing that enforces it.
 *
 * It did not. `FilesController` carried only `JwtAuthGuard`, no `@RequireFeature`, and
 * the `videoMessages` entitlement flag was referenced nowhere outside the entitlements
 * service — any signed-in user, free included, could upload 500 MB legacy videos. These
 * pin the gate, and just as importantly pin what must stay OPEN:
 *
 *   - death_certificate / id_document are never gated (a bereaved family filing a claim
 *     and a member verifying their ID are not upsell moments), and
 *   - reading, listing and deleting an existing video stay open, so a lapsed member can
 *     still reach and remove what they already recorded.
 */
describe('video legacy uploads require the Premium entitlement', () => {
  const makeService = (hasVideo: boolean) => {
    const storage: any = {
      configured: true,
      presignUpload: jest.fn(async ({ key }: any) => ({ uploadUrl: `https://s3/put/${key}`, key })),
    };
    const prisma: any = {
      fileObject: {
        aggregate: jest.fn(async () => ({ _sum: { sizeBytes: 0 } })),
        create: jest.fn(async ({ data }: any) => ({ id: 'new', ...data })),
      },
      user: { findUnique: jest.fn(async () => ({ scheduledPurgeAt: null })) },
      $transaction: jest.fn(async (fn: any) => fn(prisma)),
    };
    const config: any = { get: () => undefined };
    const entitlements: any = { hasFeature: jest.fn(async (_u: string, f: string) => f === 'videoMessages' && hasVideo) };
    const svc = new FilesService(storage, prisma, config, entitlements);
    return { svc, storage, prisma, entitlements };
  };

  describe('a member WITHOUT the feature', () => {
    it('cannot presign a legacy video, and no URL is ever minted', async () => {
      const { svc, storage } = makeService(false);
      await expect(svc.presignUpload('user-1', 'video_legacy', 'video/mp4', 1000)).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(storage.presignUpload).not.toHaveBeenCalled();
    });

    it('cannot confirm one either — a held presigned URL is not a way in', async () => {
      const { svc, prisma } = makeService(false);
      await expect(
        svc.confirmUpload('user-1', 'video_legacy', 'legacy-videos/user-1/a.mp4', 'video/mp4', 1000),
      ).rejects.toBeInstanceOf(ForbiddenException);
      expect(prisma.fileObject.create).not.toHaveBeenCalled();
    });

    it('CAN still upload a death certificate — a claim must never hit a paywall', async () => {
      const { svc, storage } = makeService(false);
      const res = await svc.presignUpload('user-1', 'death_certificate', 'application/pdf', 1000);
      expect(res.kind).toBe('death_certificate');
      expect(storage.presignUpload).toHaveBeenCalled();
    });

    it('CAN still upload an ID document — verification is not a sold feature', async () => {
      const { svc, storage } = makeService(false);
      const res = await svc.presignUpload('user-1', 'id_document', 'image/jpeg', 1000);
      expect(res.kind).toBe('id_document');
      expect(storage.presignUpload).toHaveBeenCalled();
    });

    it('does not consult entitlements at all for an ungated kind', async () => {
      const { svc, entitlements } = makeService(false);
      await svc.presignUpload('user-1', 'id_document', 'image/jpeg', 1000);
      expect(entitlements.hasFeature).not.toHaveBeenCalled();
    });
  });

  describe('a Premium member', () => {
    it('presigns a legacy video normally', async () => {
      const { svc, entitlements } = makeService(true);
      const res = await svc.presignUpload('user-1', 'video_legacy', 'video/mp4', 1000);
      expect(res.kind).toBe('video_legacy');
      expect(entitlements.hasFeature).toHaveBeenCalledWith('user-1', 'videoMessages');
    });

    it('confirms it, and the row is written', async () => {
      const { svc, prisma } = makeService(true);
      const row = await svc.confirmUpload('user-1', 'video_legacy', 'legacy-videos/user-1/a.mp4', 'video/mp4', 1000);
      expect(row).toMatchObject({ kind: 'video_legacy', userId: 'user-1' });
      expect(prisma.fileObject.create).toHaveBeenCalled();
    });
  });
});
