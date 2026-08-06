import { IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

/**
 * The two halves of the way in.
 *
 * Both are free-text "contact" fields — a phone or an email — because the family
 * member typing them does not know which of the two the deceased recorded, and making
 * them guess is a failure on the one flow that has no second chance. The service
 * discriminates on the '@'.
 */
export class ClaimLookupDto {
  // The deceased's email or phone, as the family knows it.
  @IsString()
  @MinLength(3)
  @MaxLength(320) // RFC 5321 max email length; a phone is far shorter
  deceasedContact: string;

  // The CLAIMANT's own email or phone. Not optional, and not a convenience: with only
  // the deceased's contact, one request fans a message out to every witness, trustee and
  // heir on the will. See DeathClaimsService.lookup.
  @IsString()
  @MinLength(3)
  @MaxLength(320)
  claimantContact: string;
}

/**
 * Filing the claim. Note what is ABSENT: no willId, no phone, no role. Those come from
 * the claim token and must never be accepted from the body — a caller who could name a
 * will could file a death claim against it.
 */
export class SubmitDeathClaimDto {
  @IsString()
  @MinLength(2)
  @MaxLength(200)
  submittedByName: string;

  // A confirmed upload of kind 'death_certificate'. An ID, not a URL: the server derives
  // the stored URL from it, so a reviewer can never be pointed at an attacker's host.
  @IsUUID()
  certificateFileId: string;
}

export class RejectDeathClaimDto {
  @IsString()
  @MinLength(3)
  reason: string;
}
