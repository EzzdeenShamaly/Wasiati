import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { FeatureGuard } from '../common/guards/feature.guard';
import { RequireFeature } from '../common/decorators/require-feature.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { VaultService } from './vault.service';
import { AddVaultItemDto } from './dto/add-vault-item.dto';
import { SetVaultVerifierDto } from './dto/set-vault-verifier.dto';

// Encrypted vault is a STANDARD+ feature. Server only ever stores ciphertext.
@ApiTags('vault')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, FeatureGuard)
@RequireFeature('vault')
@Controller('vault')
export class VaultController {
  constructor(private vault: VaultService) {}

  @Post('items')
  add(@CurrentUser() user: { userId: string }, @Body() body: AddVaultItemDto) {
    return this.vault.addItem(user.userId, body.label, body.ciphertext, body.encryptedDataKey);
  }

  @Get('kdf')
  @ApiOperation({
    summary: 'This vault’s PBKDF2 salt, its passphrase verifier (if set), and whether it holds items.',
  })
  kdf(@CurrentUser() user: { userId: string }) {
    return this.vault.getKdfSalt(user.userId);
  }

  /**
   * Records the passphrase check for a vault that has none — set once and never replaced.
   * The client sends it only after proving the KEK, either because the vault is empty (first
   * use) or because an existing item decrypted with it.
   */
  @Post('kdf/verifier')
  @ApiOperation({ summary: 'Store this vault’s passphrase verifier. Write-once; a later attempt is a no-op.' })
  setVerifier(@CurrentUser() user: { userId: string }, @Body() body: SetVaultVerifierDto) {
    return this.vault.setKekVerifier(user.userId, body.verifier);
  }

  @Get('items')
  list(@CurrentUser() user: { userId: string }) {
    return this.vault.listItems(user.userId);
  }

  @Delete('items/:itemId')
  remove(@CurrentUser() user: { userId: string }, @Param('itemId') itemId: string) {
    return this.vault.deleteItem(itemId, user.userId);
  }
}
