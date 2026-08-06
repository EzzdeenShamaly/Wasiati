import { BadRequestException, NotFoundException } from '@nestjs/common';

/**
 * A SEALED will is executed and final, and its ROSTER is part of what was executed.
 *
 * WillDocumentService renders the witnesses and the trustee side by side in the same
 * "Witnesses & trustee" block — each by name, role and signing/confirmation date — counts
 * the confirmed witnesses into both the header and the sealed footer ("2 witnesses
 * confirmed"), and lists them again on the signature certificate. So adding a roster row
 * after the seal, or letting a stale invitation be answered, CHANGES an executed legal
 * instrument: a fresh name appears on the attestation page of a document that was already
 * sealed, carrying a date later than the seal itself.
 *
 * Nothing enforced that. WitnessesService.addWitness and TrusteesService.addTrustee both
 * checked ownership and stopped; confirmSignature and confirm both checked the one-time
 * code and stopped. HeirContactsService.assertEditable had already applied this reasoning
 * to the roster IT owns ("a locked/non-DRAFT will is frozen") — these were the adjacent
 * paths that never picked it up.
 *
 * SUPERSEDED is frozen for the same reason: it is retained history of a will that was once
 * executed, and history that can still be written to is not history.
 *
 * DELIBERATELY NARROWER than assertEditable, which freezes anything not DRAFT:
 *
 *   - Witnessing and trustee confirmation happen ON a locked, SIGNED will. That is the
 *     point of them, so `locked` cannot be the test here.
 *   - There is no route to DELETE a witness or a trustee. Refusing to add one at SIGNED
 *     would strand an owner whose witness has an unreachable number with no way to replace
 *     the row — the exact silent dead end that notifyWitnessInvited's `notified` flag was
 *     added to surface.
 *
 * The roster therefore stays open right up to execution, and closes there.
 */
export async function assertWillNotExecuted(
  prisma: { will: { findUnique: (args: any) => Promise<{ status: string } | null> } },
  willId: string,
): Promise<void> {
  const will = await prisma.will.findUnique({ where: { id: willId }, select: { status: true } });
  if (!will) throw new NotFoundException('Will not found.');
  if (will.status === 'SEALED') {
    throw new BadRequestException(
      'This will has been sealed. Its witnesses and trustee are part of the executed document ' +
        'and cannot be changed — unpublish it, or seal a revision, to make changes.',
    );
  }
  if (will.status === 'SUPERSEDED') {
    throw new BadRequestException(
      'This will has been replaced by a newer sealed version and is kept as history, so it can ' +
        'no longer be changed.',
    );
  }
}
