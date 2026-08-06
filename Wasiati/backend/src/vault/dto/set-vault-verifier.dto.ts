import { IsString, Length } from 'class-validator';

/**
 * The vault's passphrase check: a fixed known string encrypted under the KEK, packed as
 * `nonce.ciphertext.mac` in base64.
 *
 * Opaque to the server on purpose — it has no passphrase and no KEK, so it cannot validate
 * the contents, only the shape. The bounds keep a malformed or oversized blob out of a
 * write-once column that can never be corrected afterwards.
 */
export class SetVaultVerifierDto {
  @IsString()
  @Length(16, 512)
  verifier: string;
}
