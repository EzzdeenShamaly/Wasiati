import { IsString, MinLength } from 'class-validator';

export class AddVaultItemDto {
  @IsString()
  @MinLength(1)
  label: string;

  @IsString()
  ciphertext: string;

  @IsString()
  encryptedDataKey: string;
}
